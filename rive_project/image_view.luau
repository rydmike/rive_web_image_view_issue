-- Draws one image asset twice, inside two framed squares:
--
--   left   the vector renderer draws the image (renderer:drawImage)
--   right  a GPU canvas samples the same image through Image:view()
--
-- Both squares should show the same orange and teal checker. The view is made once, as soon as the image
-- reports a size, which is how a scene uses a file image in a GPU canvas.

type Scene = {
    canvas: GPUCanvas?,
    pipeline: GPUPipeline?,
    layout: GPUBindGroupLayout?,
    sampler: GPUSampler?,
    image: Image?,
    bind: GPUBindGroup?,
    imageSampler: ImageSampler,
    frame: Path,
    framePaint: Paint,
}

local LEFT = 20
local RIGHT = 220
local TOP = 120
local SIZE = 160

local function init(self: Scene, context: Context): boolean
    self.image = context:image('checker')
    for _, x in { LEFT, RIGHT } do
        self.frame:moveTo(Vector.xy(x - 4, TOP - 4))
        self.frame:lineTo(Vector.xy(x + SIZE + 4, TOP - 4))
        self.frame:lineTo(Vector.xy(x + SIZE + 4, TOP + SIZE + 4))
        self.frame:lineTo(Vector.xy(x - 4, TOP + SIZE + 4))
        self.frame:close()
    end
    local shader = context:shader('image_view')
    if shader == nil then
        return true
    end
    local canvas = context:gpuCanvas()
    self.canvas = canvas
    local layout = GPUBindGroupLayout.new({ shader = shader, groupIndex = 0 })
    self.layout = layout
    self.pipeline = GPUPipeline.new({
        vertex = { module = shader, entryPoint = 'vs_main' },
        fragment = { module = shader, entryPoint = 'fs_main' },
        bindGroupLayouts = { layout },
        vertexLayout = {},
        colorTargets = { { format = canvas.format } },
        cullMode = 'none',
    })
    self.sampler = GPUSampler.new({ min = 'linear', mag = 'linear' })
    return true
end

local function measure(self: Scene): Vector
    return Vector.xy(400, 400)
end

local function resize(self: Scene, size: Vector, scale: number)
    local canvas = self.canvas
    local width, height = math.ceil(size.x * scale), math.ceil(size.y * scale)
    if canvas and width >= 1 and height >= 1 then
        canvas:resize(width, height)
    end
end

local function advance(self: Scene, seconds: number): boolean
    return true
end

local function draw(self: Scene, renderer: Renderer)
    renderer:drawPath(self.frame, self.framePaint)
    local image = self.image
    if image == nil or image.width <= 0 then
        return
    end
    renderer:save()
    renderer:transform(Mat2D.withTranslation(LEFT, TOP) * Mat2D.withScale(SIZE / image.width, SIZE / image.height))
    renderer:drawImage(image, self.imageSampler, 'srcOver', 1)
    renderer:restore()

    local canvas, pipeline, layout, sampler = self.canvas, self.pipeline, self.layout, self.sampler
    if canvas == nil or pipeline == nil or layout == nil or sampler == nil or canvas.width < 1 then
        return
    end
    if self.bind == nil then
        self.bind = GPUBindGroup.new({
            layout = layout,
            textures = { { slot = 0, view = image:view() } },
            samplers = { { slot = 1, sampler = sampler } },
        })
    end
    local pass = canvas:beginRenderPass({
        color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 0 } } },
    })
    local bind = self.bind
    if bind then
        pass:setPipeline(pipeline)
        pass:setBindGroup(0, bind)
        pass:draw(6, 1)
    end
    pass:finish()
    renderer:drawImage(canvas.image, self.imageSampler, 'srcOver', 1)
end

return function(context: Context): Layout<Scene>
    return {
        canvas = nil,
        pipeline = nil,
        layout = nil,
        sampler = nil,
        image = nil,
        bind = nil,
        imageSampler = ImageSampler('clamp', 'clamp', 'bilinear'),
        frame = Path.new(),
        framePaint = Paint.with({ color = Color.rgb(90, 98, 110), style = 'stroke', thickness = 2 }),
        init = init,
        measure = measure,
        resize = resize,
        advance = advance,
        draw = draw,
    }
end
