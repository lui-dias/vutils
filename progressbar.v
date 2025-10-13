module main

import term
import time
import math
import rand

const block = '\u2588'

struct Widget {
	name   string
	render fn (pb ProgressBar, w int, remaining_w int) string @[required]
	lazy   bool
}

struct ProgressBar {
mut:
	current  f64           @[required]
	total    f64           @[required]
	widgets  []Widget      @[required]
	interval time.Duration @[required]

	running     bool = true
	widgets_map map[string]string
	start_time  time.Time
}

fn (mut pb ProgressBar) start() {
	print('\x1b[?25l') // hide cursor

	pb.start_time = time.now()

	for widget in pb.widgets {
		pb.widgets_map[widget.name] = ''
	}

	for pb.running {
		pb.render()
	}

	pb.render()
}

fn (mut pb ProgressBar) render() {
	w, _ := term.get_terminal_size()
	mut remaining_w := w

	for widget in pb.widgets {
		if !widget.lazy {
			s := widget.render(pb, w, remaining_w)
			remaining_w -= s.runes().len
			pb.widgets_map[widget.name] = s
		}
	}

	for widget in pb.widgets {
		if widget.lazy {
			s := widget.render(pb, w, remaining_w)
			remaining_w -= s.runes().len
			pb.widgets_map[widget.name] = s
		}
	}

	widgets_str := pb.widgets_map.values().join('')
	empty := ' '.repeat(remaining_w)

	print('\r${widgets_str}${empty}')
	flush_stdout()

	time.sleep(pb.interval)
}

fn widget_string(s string) Widget {
	return Widget{
		name:   'string_${rand.string(10)}'
		render: fn [s] (pb ProgressBar, w int, remaining_w int) string {
			return s
		}
	}
}

fn widget_dynamic_string(a_fn fn (pb ProgressBar, w int, remaining_w int) string) Widget {
	return Widget{
		name:   'dynamic_string_${rand.string(10)}'
		render: fn [a_fn] (pb ProgressBar, w int, remaining_w int) string {
			return a_fn(pb, w, remaining_w)
		}
	}
}

fn widget_percentage() Widget {
	return Widget{
		name:   'percentage'
		render: fn (pb ProgressBar, w int, remaining_w int) string {
			percent := int(pb.current / pb.total * 100)
			return '${percent}%'
		}
	}
}

fn widget_bar() Widget {
	return Widget{
		name:   'bar'
		lazy:   true
		render: fn (pb ProgressBar, w int, remaining_w int) string {
			// -1 to prevent adding an extra block at the 100%
			filled := int(pb.current / pb.total * remaining_w) - 1

			bar := block.repeat(filled)
			empty := ' '.repeat(remaining_w - bar.runes().len)
			return '${bar}${empty}'
		}
	}
}

fn widget_time() Widget {
	return Widget{
		name:   'time'
		render: fn (pb ProgressBar, w int, remaining_w int) string {
			seconds_ := time.since(pb.start_time).seconds()

			hours := int(seconds_ / 3600)
			minutes := int(math.fmod(seconds_, 3600) / 60)
			seconds := int(math.fmod(seconds_, 60))

			return '${hours:02}:${minutes:02}:${seconds:02}'
		}
	}
}

fn widget_eta() Widget {
	return Widget{
		name:   'eta'
		render: fn (pb ProgressBar, w int, remaining_w int) string {
			if pb.current == 0 {
				return 'ETA 00:00:00'
			}

			diff_seconds := time.since(pb.start_time).seconds()

			// https://github.com/doches/progressbar/blob/ac56232610abf58cc2db2bc86efc8fcba7dfe8c2/lib/progressbar.c#L143
			eta := (diff_seconds / pb.current) * (pb.total - pb.current)

			hours := int(eta / 3600)
			minutes := int(math.fmod(eta, 3600) / 60)
			seconds := int(math.fmod(eta, 60))

			return 'ETA ${hours:02}:${minutes:02}:${seconds:02}'
		}
	}
}
