## Vutils

Single-file libraries I'd like for V

NOTE: It have bugs and missing features

### How to Use

Ctrl+C + Ctrl+V

### Progressbar and Subprocess example

```v
module main

import time
import regex

fn match_frame(s string) f64 {
	mut re := regex.regex_opt(r'frame= *(\d+) ') or { panic(err) }
	re.match_string(s)
	start, end := re.get_group_bounds_by_id(0)

	if start == -1 || end == -1 {
		return 0
	}
	return s[start..end].f64()
}

fn main() {
	mut e := Execute{
		command: 'ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 "a.mp4"'
		stdout:  .pipe
	}
	e.run()
	if e.wait() > 0 {
		eprintln_exit('Process failed (${e.exit_code}).\n${e.stdout_read()}')
	}

	frames_count := e.stdout_read().f64()

	mut pb := &ProgressBar{
		current:  f64(0)
		total:    frames_count
		widgets:  [
			widget_dynamic_string(fn (pb ProgressBar, w int, remaining_w int) string {
				return 'Frames ${pb.current:.0}/${pb.total:.0}'
			}),
			widget_string(' '),
			widget_string('['),
			widget_percentage(),
			widget_string('] |'),
			widget_bar(),
			widget_string('| '),
			widget_string(' '),
			widget_time(),
			widget_string(' - '),
			widget_eta(),
		]
		interval: time.second
	}

	e = Execute{
		command: 'ffmpeg -i a.mp4 -c:v libsvtav1 -y b.mp4'
		stderr:  .pipe
	}

	e.run()
	go pb.start()

	for i in e.stderr_iter() {
		c := match_frame(i)

		if c > 0 {
			pb.current = c

			if pb.current >= frames_count {
				break
			}
		}
	}

	pb.current = frames_count
	pb.running = false
	pb.wait()
}
```
![progressbar and subprocess example](assets/progressbar-subprocess.png)