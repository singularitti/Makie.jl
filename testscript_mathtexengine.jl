using CairoMakie: Cairo
# using CairoMakie
using GLMakie

CairoMakie.activate!(type = "svg")


##

struct MyTex <: AbstractString
    s::String
end

MakieLayout.iswhitespace(t::MyTex) = t.s == ""
Base.isempty(::MyTex) = false

##
t = Node(MyTex("\\sum_k{3.002}"))
let
    s = Scene(camera = campixel!)
    text!(s,
        t,
        position = (100, 100),
        textsize = 20,
        show_axis = false)
    sl = Slider(s, bbox = BBox(10, 200, 10, 30))
    on(sl.value) do v
        t[] = MyTex("\\sum_k{$v} + \\int_{$v}^{$v}xyz")
    end
    notify(sl.value)
    s
end

##
let
    s = Scene(camera = campixel!)
    text!(s,
        ["hello", "what's up"],
        position = [(100, 100), (200, 200)],
        textsize = 20,
        space = :data,
        show_axis = false)
    s
end
##

function Makie.plot!(plot::Makie.Text{<:Tuple{MyTex}})

    # attach a function to any text that calculates the glyph layout and stores it
    lineels_glyphlayout_offset = lift(plot[1], plot.textsize, plot.align, plot.rotation, plot.model) do mytex, ts, al, rot, mo
        ts = to_textsize(ts)
        rot = to_rotation(rot)

        tex_elements, glyphlayout = texelems_and_glyph_collection(mytex, ts, al[1], al[2], rot)
    end

    glyphlayout = @lift($lineels_glyphlayout_offset[2])


    linepairs = Node(Tuple{Point2f0, Point2f0}[])
    linewidths = Node(Float32[])

    onany(lineels_glyphlayout_offset, plot.position, plot.textsize, plot.rotation) do (allels, _, offs), pos, ts, rot

        ts = to_textsize(ts)
        rot = convert_attribute(rot, key"rotation"())

        offset = Point2f0(pos)

        els = map(allels) do el
            if el[1] isa VLine
                h = el[1].height
                t = el[1].thickness * ts
                pos = el[2]
                size = el[3]
                ps = (Point2f0(pos[1], pos[2]) .* ts, Point2f0(pos[1], pos[2] + h) .* ts) .- Ref(offs)
                ps = Ref(rot) .* to_ndim.(Point3f0, ps, 0)
                ps = Point2f0.(ps) .+ Ref(offset)
                (ps, t)
            elseif el[1] isa HLine
                w = el[1].width
                t = el[1].thickness * ts
                pos = el[2]
                size = el[3]
                ps = (Point2f0(pos[1], pos[2]) .* ts, Point2f0(pos[1] + w, pos[2]) .* ts) .- Ref(offs)
                ps = Ref(rot) .* to_ndim.(Point3f0, ps, 0)
                ps = Point2f0.(ps) .+ Ref(offset)
                (ps, t)
            else
                nothing
            end
        end
        pairs = filter(!isnothing, els)
        linewidths.val = repeat(last.(pairs), inner = 2)
        linepairs[] = first.(pairs)
        # @show linepairs
    end

    notify(plot.position)

    if !(glyphlayout isa Observable{<:Makie.GlyphCollection2})
        error("Incorrect type parameter $(typeof(glyphlayout))")
    end

    text!(plot, glyphlayout; plot.attributes...)
    # linesegments!(plot, linepairs, linewidth = linewidths)
    linesegments!(plot, linepairs, linewidth = linewidths, color = plot.color)

    plot
end

##


function texelems_and_glyph_collection(str::MyTex, fontscale_px, halign, valign, rotation)

    rot = Makie.convert_attribute(rotation, key"rotation"())

    all_els = generate_tex_elements(str.s)
    els = filter(x -> x[1] isa TeXChar, all_els)

    # hacky, but attr per char needs to be fixed
    fs = Vec2f0(first(fontscale_px))

    scales_2d = [Vec2f0(x[3] * Vec2f0(fs)) for x in els]

    chars = [x[1].char for x in els]
    fonts = [x[1].font for x in els]

    extents = [Makie.FreeTypeAbstraction.get_extent(f, c) for (f, c) in zip(fonts, chars)]

    bboxes = map(extents, fonts, scales_2d) do ext, font, scale
        unscaled_hi_bb = Makie.FreeTypeAbstraction.height_insensitive_boundingbox(ext, font)
        hi_bb = FRect2D(
            Makie.origin(unscaled_hi_bb) * scale,
            widths(unscaled_hi_bb) * scale
        )
    end

    basepositions = [to_ndim(Vec3f0, fs, 0) .* to_ndim(Point3f0, x[2], 0)
        for x in els]

    bb = isempty(bboxes) ? BBox(0, 0, 0, 0) : begin
        mapreduce(union, zip(bboxes, basepositions)) do (b, pos)
            FRect2D(FRect3D(b) + pos)
        end
    end


    xshift = if halign == :center
        width(bb) / 2
    elseif halign == :left
        minimum(bb)[1]
    elseif halign == :right
        maximum(bb)[1]
    end

    yshift = if valign == :center
        maximum(bb)[2] - (height(bb) / 2)
    elseif valign == :top
        maximum(bb)[2]
    else
        minimum(bb)[2]
    end

    positions = basepositions .- Ref(Point3f0(xshift, yshift, 0))
    positions .= Ref(rot) .* positions

    pre_align_gl = Makie.GlyphCollection2(
        chars,
        fonts,
        Point3f0.(positions),
        extents,
        scales_2d,
        fill(rot, length(chars)),
    )

    all_els, pre_align_gl, Point2f0(xshift, yshift)
end
##
with_theme() do
    f, ax , l = lines(cumsum(randn(1000)),
        axis = (
            title = L"\sum_k{x y_k}",
            xlabel = L"\lim_{x →\infty} A^j v_{(a + b)_k}^i \sqrt{23.5} x!= \sqrt{\frac{1+6}{4+a+g}}\int_{0}^{2π} \sin(x) dx",
            ylabel = L"x + y - sin(x) × tan(y) + \sqrt{2}",
        ),
        figure = (fontsize = 18, font = raw".\dev\MathTeXEngine\assets\fonts\NewCM10-Regular.otf")
    )
    text!(L"\int_{0}^{2π} \sin(x) dx", position = (500, 0))

    Legend(f[1, 2], [l, l, l], [L"\sum{xy}", L"a\int_0^5x^2+2ab", L"||x-y||^2"])
    display(f)
end
# save("test.pdf", f)
##
begin
    s = Scene(camera = campixel!)
    t = text!(s,
        L"\sqrt{2}",
        position = (50, 50),
        rotation = pi/2,
        show_axis = false,
        space = :data)
    display(s)
end

##
s = Scene(camera = campixel!)
t = text!(s,
    "hi what's up?",
    position = (50, 50),
    rotation = 0.0,
    color = :red,
    show_axis = false,
    space = :data)
s

##

s = Scene(camera = campixel!)
t = text!(s,
    L"\int_0^5x^2+2ab",
    position = Point2f0(50, 50),
    rotation = 0.0,
    show_axis = false,
    space = :data)
wireframe!(s, boundingbox(t))
s

##

s = Scene(camera = campixel!)
t = text!(s,
    [L"\int_0^5x^2+2ab", L"\int_0^5x^2+2ab"],
    position = Point2f0[(50, 50), (100, 100)],
    rotation = 0.0,
    show_axis = false,
    space = :data)
# wireframe!(s, boundingbox(t))
s

## length update test

s = Scene(camera = campixel!)
textnode = Node([L"\int_0^5x^2+2ab", L"\int_0^5x^2+2ab"])
posnode = Node(Point2f0[(50, 50), (100, 100)])

t = text!(s,
    textnode,
    position = posnode,
    rotation = 0.0,
    show_axis = false,
    space = :data)

display(s)

## change lengths

textnode.val = push!(textnode[], L"\int_0^5x^2+2ab")
posnode[] = push!(posnode[], Point2f0(150, 150))

## length update test annotation style

s = Scene(camera = campixel!)
textposnode = Node([
    (L"\int_0^5x^2+2ab", Point2f0(50, 50)),
    (L"\int_0^5x^2+2ab", Point2f0(100, 100)),
])

t = text!(s,
    textposnode,
    show_axis = false,
    space = :data)

display(s)

## change lengths

textposnode[] = push!(textposnode[], (L"\int_0^5x^2+2ab", Point2f0(150, 150)))

##

lines(0..25, x -> 4 * sin(x) / (cos(3x) + 4), figure = (fontsize = 25, font = "Times"),
    axis = (
        xticks = (0:10:20, [L"10^{-3.5}", L"10^{-4.5}", L"10^{-5.5}"]),
        yticks = ([-1, 0, 1], [L"\sum_%$i{xy}" for i in 1:3]),
        yticklabelrotation = pi/8,
        title = L"\int_0^1{x^2}",
        xlabel = L"\sum_k{x_k ⋅ y_k}",
        ylabel = L"\int_a^b{\sqrt{abx}}"
    ),
)
# text!(L"f(x) = \frac{sin(x)}{cos(3x) + 4}", position = (15, 2))
current_figure()


## dynamic ticks with MathTeXEngine

# Data

# easy to understand
# coherent formatting
# correctly dated
# sufficient information content to retrace steps
# not so detailed / time-intensive as to hinder the actual work
# write down implicit assumptions

lines(0..25, x -> 4 * sin(x) / (cos(3x) + 4), figure = (fontsize = 25, font = "Times"),
    axis = (
        xtickformat = (xs -> [L"\sqrt{%$x}+\sum" for x in xs]),
    )
)