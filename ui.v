import gg
import math { floor, round }
import arrays
import strings

// =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
//                 Enums
// =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

enum Sizing as u8 {
	fit
	fill
	fixed
}

enum Direction as u8 {
	vertical
	horizontal
}

enum TextWrap as u8 {
	no_wrap
	wrap_by_space
	wrap_by_newline
}

// =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
//                 Structs
// =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

struct Padding {
	top    int
	right  int
	bottom int
	left   int
}

struct Border {
	color   Color
	padding Padding = Padding.all(0)
	radius  int
}

struct Color {
	r u8
	g u8
	b u8
	a u8 = 255
}

struct Text {
	content      string
	wrap         TextWrap = .wrap_by_space
	line_spacing int      = 4
	size         int      = 16
	color        Color    = Color.from_hex(0x000000)
mut:
	internal__rendered_text_lines []string
}

// =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
//                 Methods
// =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

fn Padding.horizontal(n int) Padding {
	return Padding{
		left:  n
		right: n
	}
}

fn Padding.vertical(n int) Padding {
	return Padding{
		top:    n
		bottom: n
	}
}

fn Padding.all(n int) Padding {
	return Padding{
		top:    n
		right:  n
		bottom: n
		left:   n
	}
}

fn (p Padding) width() int {
	return p.left + p.right
}

fn (p Padding) height() int {
	return p.top + p.bottom
}

fn (b Border) width() int {
	return b.padding.width()
}

fn (b Border) height() int {
	return b.padding.height()
}

fn (c Color) to_gg() gg.Color {
	return gg.Color{c.r, c.g, c.b, c.a}
}

fn Color.from_gg(c gg.Color) Color {
	return Color{c.r, c.g, c.b, c.a}
}

fn Color.from_hex(hex int) Color {
	return Color.from_gg(gg.hex(hex))
}

fn Color.from_rgb(r u8, g u8, b u8) Color {
	return Color{r, g, b, 255}
}

fn Color.from_rgba(r u8, g u8, b u8, a u8) Color {
	return Color{r, g, b, a}
}

// https://stackoverflow.com/a/9493060
// [0-360] [0-100] [0-100]
fn Color.from_hsl(hh f64, ss f64, ll f64) Color {
	h := hh / 360
	s := ss / 100
	l := ll / 100

	mut r := 0.0
	mut g := 0.0
	mut b := 0.0

	if s == 0 {
		// achromatic
		r = l
		g = l
		b = l
	} else {
		q := if l < 0.5 { l * (1 + s) } else { l + s - l * s }
		p := 2 * l - q

		r = hue_to_rgb(p, q, h + 1 / 3.0)
		g = hue_to_rgb(p, q, h)
		b = hue_to_rgb(p, q, h - 1 / 3.0)
	}

	return Color{
		r: u8(round(r * 255))
		g: u8(round(g * 255))
		b: u8(round(b * 255))
	}
}

fn hue_to_rgb(p f64, q f64, tt f64) f64 {
	mut t := tt

	if t < 0 {
		t += 1
	}
	if t > 1 {
		t -= 1
	}
	if t < 1 / 6.0 {
		return p + (q - p) * 6 * t
	}
	if t < 1 / 2.0 {
		return q
	}
	if t < 2 / 3.0 {
		return p + (q - p) * (2 / 3.0 - t) * 6
	}
	return p
}

fn (t Text) to_gg_text_cfg() gg.TextCfg {
	return gg.TextCfg{
		color: t.color.to_gg()
		size:  t.size
	}
}

// =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
//                 UI
// =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

struct State {
mut:
	ctx &gg.Context = unsafe { nil }
	e   &Element    = unsafe { nil }
}

struct Element {
	name string
mut:
	x        int
	y        int
	w        int
	h        int
	parent   &Element = unsafe { nil }
	children []Element

	sizing_w  Sizing    = .fit
	sizing_h  Sizing    = .fit
	direction Direction = .vertical
	padding   Padding   = Padding.all(0)
	spacing   int

	background Color
	border     &Border = unsafe { nil }
	radius     int

	text &Text = unsafe { nil }
}

fn layout_add_parent(mut e Element) {
	for mut c in e.children {
		c.parent = e

		layout_add_parent(mut c)
	}
}

// Set sizing to .fixed if w or h was defined
fn layout_adjust_sizing(mut e Element) {
	if e.w > 0 {
		e.sizing_w = .fixed
	}
	if e.h > 0 {
		e.sizing_h = .fixed
	}

	for mut c in e.children {
		layout_adjust_sizing(mut c)
	}
}

// Set size of parent with the size of fixed children
// Solves FIT sizing
fn layout_size(mut e Element) {
	mut ws := []int{}
	mut hs := []int{}

	for mut c in e.children {
		layout_size(mut c)

		if e.sizing_w != .fixed {
			ws << c.w
		}
		if e.sizing_h != .fixed {
			hs << c.h
		}
	}

	if ws.len > 0 {
		biggest_w := arrays.max(ws) or { panic(err) }
		sum_w := arrays.sum(ws) or { panic(err) }

		e.w = if e.direction == .horizontal { sum_w } else { biggest_w }
	}
	if hs.len > 0 {
		biggest_h := arrays.max(hs) or { panic(err) }
		sum_h := arrays.sum(hs) or { panic(err) }

		e.h = if e.direction == .vertical { sum_h } else { biggest_h }
	}
}

// Solves FILL sizing
fn layout_fill_size(mut e Element) {
	spacing := int_max(0, e.children.len - 1) * e.spacing

	mut remaining_w := e.w - e.padding.width() - spacing
	mut remaining_h := e.h - e.padding.height() - spacing

	mut idx_children_with_fill_w := []int{}
	mut idx_children_with_fill_h := []int{}

	for i, c in e.children {
		if c.sizing_w == .fill {
			idx_children_with_fill_w << i
		}
		if c.sizing_h == .fill {
			idx_children_with_fill_h << i
		}
	}

	for c in e.children {
		if e.direction == .horizontal && c.sizing_w == .fixed {
			remaining_w -= c.w
		}
		if e.direction == .vertical && c.sizing_h == .fixed {
			remaining_h -= c.h
		}
	}

	for i in idx_children_with_fill_w {
		e.children[i].w = int(floor(remaining_w / idx_children_with_fill_w.len))
	}
	for i in idx_children_with_fill_h {
		e.children[i].h = int(floor(remaining_h / idx_children_with_fill_h.len))
	}

	for mut c in e.children {
		layout_fill_size(mut c)
	}
}

fn layout_border(mut e Element) {
	e.w -= e.border.width()
	e.h -= e.border.height()

	for mut c in e.children {
		layout_border(mut c)
	}
}

fn layout_text_wrap(mut e Element, ctx gg.Context) {
	if !isnil(e.text) {
		if e.text.wrap == .wrap_by_space {
			ctx.set_text_cfg(e.text.to_gg_text_cfg())
			mut space_left := e.parent.w

			tokens := e.text.content.split(if e.text.wrap == .wrap_by_space { ' ' } else { '\n' })
			space_width := ctx.text_width(' ')

			mut sb := strings.new_builder(512)

			for t in tokens {
				if t == '\n' {
					sb.write_string('\n')
					space_left = e.parent.w

					continue
				}

				word_width := ctx.text_width(t)
				space_left -= word_width + space_width

				if space_left <= 0 {
					sb.go_back(1)
					sb.write_string('\n')
					space_left = e.parent.w - word_width - space_width
				}

				sb.write_string(t + ' ')
			}

			e.text.internal__rendered_text_lines = sb.str().trim_space().split_into_lines()
		} else if e.text.wrap == .wrap_by_newline {
			e.text.internal__rendered_text_lines = e.text.content.split_into_lines()
		} else {
			e.text.internal__rendered_text_lines = [e.text.content]
		}
	}

	for mut c in e.children {
		layout_text_wrap(mut c, ctx)
	}
}

fn layout_positions(mut e Element, offset_x int, offset_y int) {
	e.x = offset_x
	e.y = offset_y

	mut x := e.x + e.padding.left
	mut y := e.y + e.padding.top

	for mut c in e.children {
		layout_positions(mut c, x, y)

		if e.direction == .horizontal {
			x += c.w + e.spacing
		} else {
			y += c.h + e.spacing
		}
	}
}

fn layout(mut e Element, ctx gg.Context) {
	layout_add_parent(mut e)
	layout_adjust_sizing(mut e)

	// It define or need the value of a child
	// if it doesn't have children, it's unnecessary to run
	if e.children.len > 0 {
		layout_size(mut e)
		layout_fill_size(mut e)
	}

	if !isnil(e.border) {
		layout_border(mut e)
	}

	layout_positions(mut e, 0, 0)
	layout_text_wrap(mut e, ctx)
	// exit(0)
}

fn render(ctx gg.Context, e Element) {
	// println('${e.name} ${e.x}, ${e.y}, ${e.w}, ${e.h}')

	border := if isnil(e.border) { &Border{} } else { e.border }

	ctx.draw_rect(
		x:          e.x + border.padding.left
		y:          e.y + border.padding.top
		w:          e.w - border.padding.right * 2
		h:          e.h - border.padding.bottom * 2
		is_rounded: e.radius > 0
		radius:     e.radius
		style:      .fill
		color:      e.background.to_gg()
	)

	if !isnil(e.border) {
		ctx.draw_rect(
			x:          e.x
			y:          e.y
			w:          e.w
			h:          e.h
			is_rounded: e.border.radius > 0
			radius:     e.border.radius
			style:      .stroke
			color:      e.border.color.to_gg()
		)
	}

	if !isnil(e.text) {
		mut i := 0

		for line in e.text.internal__rendered_text_lines {
			ctx.draw_text(e.x, e.y + i, line, e.text.to_gg_text_cfg())
			i += e.text.line_spacing + ctx.text_height(line)
		}
	}

	if !isnil(e.children) {
		for c in e.children {
			render(ctx, c)
		}
	}
}

fn frame_fn(mut state State) {
	state.ctx.begin()
	render(state.ctx, state.e)
	state.ctx.end()
}

fn init_fn(mut s State) {
	layout(mut s.e, s.ctx)
}

fn main() {
	mut state := &State{}

	mut e := Element{
		name:       'a'
		w:          800
		h:          600
		background: Color.from_hex(0x181818)
		children:   [
			Element{
				name:       'b'
				background: Color.from_hex(0x634747)
				sizing_w:   .fill
				sizing_h:   .fill
				direction:  .horizontal
				padding:    Padding{
					top: 4
					// right:  32
					bottom: 8
					// left:   16
				}
				spacing:    20
				children:   [
					Element{
						name:       'c'
						background: Color.from_hex(0xff0000)
						children:   []
						w:          50
						h:          150
					},
					Element{
						name:       'd'
						background: Color.from_hex(0xd845ca)
						children:   []
						h:          50
						sizing_w:   .fill
						border:     &Border{
							padding: Padding.vertical(8)
							color:   Color.from_hex(0x2da86c)
						}
					},
					Element{
						name:       'e'
						background: Color.from_hex(0x4882ba)
						children:   [
							Element{
								name:     'f'
								text:     &Text{
									content: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua'
									color:   Color.from_hex(0xff0000)
									size:    32
								}
								children: []
							},
						]
						w:          200
						sizing_h:   .fill
					},
				]
			},
		]
	}

	state.e = &e
	state.ctx = gg.new_context(
		bg_color:     gg.rgb(174, 198, 255)
		width:        800
		height:       600
		window_title: 'Polygons'
		user_data:    state
		frame_fn:     frame_fn
		init_fn:      init_fn
	)

	state.ctx.run()

	// println('================')
	// println(e.children[0])
	// println(e.children[0].children[1])
}
