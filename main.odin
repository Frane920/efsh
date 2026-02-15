package main

import "core:sys/linux"

_ascii_space := [256]bool {
	'\t' = true,
	'\n' = true,
	'\v' = true,
	'\f' = true,
	'\r' = true,
	' '  = true,
}

buffer := [1024]u8{}
env_buffer := [4096]u8{}
env_len := 0
exit_code := 0

foreign _ {
	@(link_name = "asm_exit")
	exit :: proc(code: int) -> ! ---
	@(link_name = "asm_write")
	write :: proc(fd: i32, s: string) ---
	@(link_name = "asm_read")
	read :: proc(fd: i32, buffer_ptr: [^]u8, buffer_len: int) -> int ---
}

init_env :: proc() {
	path := "/proc/self/environ"
	path_cstr := to_cstring(path, context.temp_allocator)

	fd, errno := linux.open(path_cstr, {.RDWR}, {})
	if errno != .NONE {return}

	n, _ := linux.read(fd, env_buffer[:])
	env_len = n
	linux.close(fd)
}

get_env :: proc(key: string) -> string {
	if env_len == 0 {return ""}

	cursor := 0
	for cursor < env_len {
		start := cursor

		end := start
		for end < env_len && env_buffer[end] != 0 {
			end += 1
		}

		entry := string(env_buffer[start:end])

		cursor = end + 1

		if len(entry) > len(key) && entry[len(key)] == '=' {
			if entry[:len(key)] == key {
				return entry[len(key) + 1:]
			}
		}
	}
	return ""
}

set_env :: proc(key, val: string) {
	// 1. Prepare the full "KEY=VAL" string
	full_entry := join({key, "=", val}, "", context.temp_allocator)
	entry_len := len(full_entry)

	// 2. Try to find the existing key in env_buffer
	cursor := 0
	for cursor < env_len {
		start := cursor
		end := start
		for end < env_len && env_buffer[end] != 0 {end += 1}

		entry := string(env_buffer[start:end])

		// Check if this is the key we are looking for
		if len(entry) > len(key) && entry[len(key)] == '=' && entry[:len(key)] == key {
			// Found it!
			// If new value fits in the old slot, overwrite it.
			// Otherwise, we'll just append a new one at the end (simplest for a raw buffer).
			if entry_len <= len(entry) {
				copy(env_buffer[start:], full_entry)
				// If it's shorter, we need to ensure we don't leave old characters
				// by shifting the null terminator or zeroing.
				if entry_len < len(entry) {
					for i in entry_len ..< len(entry) {env_buffer[start + i] = 0}
				}
				return
			}
			// If it doesn't fit, we "invalidate" the old entry by setting its first char to 0
			// and fall through to the append logic.
			env_buffer[start] = 0
			break
		}
		cursor = end + 1
	}

	// 3. Append to the end of the buffer
	// Ensure we have space for: the new entry + a null terminator
	if env_len + entry_len + 1 <= len(env_buffer) {
		copy(env_buffer[env_len:], full_entry)
		env_len += entry_len
		env_buffer[env_len] = 0
		env_len += 1
	} else {
		write(2, "Error: env_buffer is full\n")
	}
}

find_path :: proc(cmd: string, allocator := context.temp_allocator) -> cstring {
	if contains(cmd, "/") {
		return to_cstring(cmd, allocator)
	}

	path_env := get_env("PATH")
	if path_env == "" {
		path_env = "/usr/bin:/bin"
	}

	directories := split(path_env, ':', allocator)

	for dir in directories {
		if len(dir) == 0 do continue

		full_path := join({dir, "/", cmd}, "", allocator)
		c_path := to_cstring(full_path, allocator)

		stat: linux.Stat
		if linux.stat(c_path, &stat) == .NONE {
			return c_path
		}
	}
	return to_cstring(cmd, allocator)
}

execve :: proc(prog: string, argv: []cstring) {
	if contains(prog, "/") {
		p_cstr := to_cstring(prog, context.temp_allocator)
		linux.execve(p_cstr, raw_data(argv), nil)
		return
	}

	path_env := get_env("PATH")
	paths := split(path_env, ':', context.temp_allocator)

	for p in paths {
		full_path := join({p, "/", prog}, "", context.temp_allocator)
		c_path := to_cstring(full_path, context.temp_allocator)

		linux.execve(c_path, raw_data(argv), nil)
	}
}

read_line :: proc(buf: []u8) -> (string, bool) {
	for i in 0 ..< len(buf) do buf[i] = 0
	n := read(0, raw_data(buf), len(buf))
	s := string(buf[:n])
	return trim_space(s), true
}

itoa :: proc(buf: []u8, n: int) -> string {
	if n == 0 do return "0"

	val := n
	is_negative := false
	if val < 0 {
		is_negative = true
		val = -val
	}
	i := len(buf)
	for val > 0 {
		i -= 1
		buf[i] = u8(val % 10) + '0'
		val /= 10
	}
	if is_negative {
		i -= 1
		buf[i] = '-'
	}
	return string(buf[i:])
}

split :: proc(s: string, char: byte, allocator := context.temp_allocator) -> []string {
	if len(s) == 0 do return nil

	n := 1
	for i in 0 ..< len(s) {
		if s[i] == char do n += 1
	}

	res := make([]string, n, allocator)

	curr_n := 0
	start := 0
	for i in 0 ..< len(s) {
		if s[i] == char {
			res[curr_n] = s[start:i]
			curr_n += 1
			start = i + 1
		}
	}
	res[curr_n] = s[start:]
	return res
}

to_cstring :: proc(s: string, allocator := context.temp_allocator) -> cstring {
	if len(s) == 0 do return ""
	b := make([]byte, len(s) + 1, allocator)
	copy(b, s)
	b[len(s)] = 0
	return cstring(&b[0])
}

trim_space :: proc(s: string) -> string {
	if len(s) == 0 do return ""

	start := 0
	if start < len(s) && _ascii_space[s[start]] {
		start += 1
	}

	if start == len(s) do return ""

	end := len(s)
	for end > start && _ascii_space[s[end - 1]] {
		end -= 1
	}

	return s[start:end]
}

contains :: proc(s, substr: string) -> bool {
	if len(substr) == 0 do return true
	if len(substr) > len(s) do return false

	if len(substr) == 1 {
		target := substr[0]
		for i in 0 ..< len(s) {
			if s[i] == target do return true
		}
		return false
	}

	for i in 0 ..< len(s) - len(substr) + 1 {
		if s[i:i + len(substr)] == substr {
			return true
		}
	}

	return false
}

fields :: proc(s: string, allocator := context.temp_allocator) -> []string {
	if len(s) == 0 do return nil

	n := 0
	in_field := false
	for i in 0 ..< len(s) {
		is_space := _ascii_space[s[i]] == true
		if !is_space && !in_field {
			in_field = true
			n += 1
		} else if is_space {
			in_field = false
		}
	}

	if n == 0 do return nil

	res := make([]string, n, allocator)
	na := 0
	field_start := -1

	for i in 0 ..< len(s) {
		is_space := _ascii_space[s[i]] == true
		if !is_space {
			if field_start == -1 do field_start = i
		} else {
			if field_start != -1 {
				res[na] = s[field_start:i]
				na += 1
				field_start = -1
			}
		}
	}

	if field_start != -1 {
		res[na] = s[field_start:]
	}

	return res
}

concatenate :: proc(a: []string, allocator := context.temp_allocator) -> string {
	if len(a) == 0 do return ""

	total_len := 0
	for s in a do total_len += len(s)

	b := make([]byte, total_len, allocator)

	offset := 0
	for s in a {
		copy(b[offset:], s)
		offset += len(s)
	}
	return string(b)
}

join :: proc(a: []string, sep: string, allocator := context.temp_allocator) -> string {
	if len(a) == 0 do return ""
	if len(a) == 1 do return a[0]

	total_len := len(sep) * (len(a) - 1)
	for s in a do total_len += len(s)

	b := make([]byte, total_len, allocator)

	offset := copy(b, a[0])
	for s in a[1:] {
		offset += copy(b[offset:], sep)
		offset += copy(b[offset:], s)
	}
	return string(b)
}

has_prefix :: proc(s, prefix: string) -> (result: bool) {
	return len(s) >= len(prefix) && s[0:len(prefix)] == prefix
}

get_username :: proc() -> string {
	return get_env("USER")
}

get_homedir :: proc() -> string {
	return get_env("HOME")
}

get_cwd :: proc() -> string {
	n, errno := linux.getcwd(buffer[:])
	if errno != .NONE || n <= 0 {
		return ""
	}
	return string(buffer[:n])
}

set_cwd :: proc(path: string) -> bool {
	cpath := to_cstring(path, context.temp_allocator)

	errno := linux.chdir(cpath)
	return errno == .NONE
}


shorten_home :: proc(path: string) -> string {
	home := get_homedir()

	if path == home {
		return "~"
	}

	if has_prefix(path, home) {
		return concatenate({"~", path[len(home):]}, context.temp_allocator)
	}

	return path
}

expand_tilde :: proc(input: string) -> string {
	home := get_homedir()
	if input == "~" {
		return home
	}
	if has_prefix(input, "~/") {
		return concatenate({home, input[1:]}, context.temp_allocator)
	}
	return input
}

expand_env :: proc(args: []string) -> []string {
	for i in 0 ..< len(args) {
		arg := args[i]
		if len(arg) < 2 || arg[0] != '$' {
			continue
		}

		nameEnd := 1
		for nameEnd < len(arg) && arg[nameEnd] != '/' && arg[nameEnd] != '.' {
			nameEnd += 1
		}

		varName := arg[1:nameEnd]

		val := get_env(varName)
		args[i] = join([]string{val, arg[nameEnd:]}, "")
	}
	return args
}

run_cmd :: proc(prog: string, args: []string) {
	argv: [128]cstring

	in_fd: linux.Fd = 0
	out_fd: linux.Fd = 1
	err_fd: linux.Fd = 2

	h_string: string
	has_h := false

	argv[0] = to_cstring(prog, context.temp_allocator)
	arg_idx := 1

	i := 0
	for i < len(args) {
		arg := args[i]

		if arg == ">" || arg == "1>" || arg == ">>" || arg == "2>" || arg == "<" || arg == "<<<" {
			if i + 1 >= len(args) do break
			target := args[i + 1]
			t_cstr := to_cstring(target, context.temp_allocator)

			switch arg {
			case ">", "1>":
				out_fd, _ = linux.open(
					t_cstr,
					{.WRONLY, .CREAT, .TRUNC},
					{.IRUSR, .IWUSR, .IRGRP, .IROTH},
				)
			case ">>":
				out_fd, _ = linux.open(
					t_cstr,
					{.WRONLY, .CREAT, .APPEND},
					{.IRUSR, .IWUSR, .IRGRP, .IROTH},
				)
			case "2>":
				err_fd, _ = linux.open(
					t_cstr,
					{.WRONLY, .CREAT, .TRUNC},
					{.IRUSR, .IWUSR, .IRGRP, .IROTH},
				)
			case "<":
				in_fd, _ = linux.open(t_cstr, {.RDWR}, {})
			case "<<<":
				h_string = target
				has_h = true
			}
			i += 2
			continue
		}

		if arg_idx < 128 - 1 {
			argv[arg_idx] = to_cstring(arg, context.temp_allocator)
			arg_idx += 1
		}
		i += 1
	}

	argv[arg_idx] = nil

	pid, errno := linux.fork()
	if errno != .NONE {
		write(2, "Fork failed\n")
		return
	}

	if pid == 0 {
		if in_fd != 0 {linux.dup2(in_fd, 0); linux.close(in_fd)}
		if out_fd != 1 {linux.dup2(out_fd, 1); linux.close(out_fd)}
		if err_fd != 2 {linux.dup2(err_fd, 2); linux.close(err_fd)}

		if has_h {
			fds: [2]linux.Fd
			linux.pipe2(&fds, {.CLOEXEC})
			linux.write(fds[1], transmute([]u8)h_string)
			linux.close(fds[1])
			linux.dup2(fds[0], 0)
			linux.close(fds[0])
		}

		execve(prog, argv[:arg_idx])
		exit(127)
	} else {
		if in_fd != 0 do linux.close(in_fd)
		if out_fd != 1 do linux.close(out_fd)
		if err_fd != 2 do linux.close(err_fd)

		status: u32
		linux.waitpid(pid, &status, {}, nil)

		exit_code := (status >> 8) & 0xFF
		exit_str := itoa(buffer[:], int(exit_code))
		set_env("?", exit_str)
	}
}

exec :: proc(input: string) {
	input := trim_space(input)
	if len(input) == 0 {return}

	if contains(input, "|") {
		commands := split(input, '|', context.temp_allocator)
		prev_read_end: linux.Fd = 0

		for i in 0 ..< len(commands) {
			cmd_str := trim_space(commands[i])
			args := fields(cmd_str, context.temp_allocator)
			args = expand_env(args[:])

			is_last := i == len(commands) - 1
			next_pipe: [2]linux.Fd

			if !is_last {
				linux.pipe2(&next_pipe, {.CLOEXEC})
			}

			pid, _ := linux.fork()
			if pid == 0 {
				if prev_read_end != 0 {
					linux.dup2(prev_read_end, 0)
					linux.close(prev_read_end)
				}

				if !is_last {
					linux.dup2(next_pipe[1], 1)
					linux.close(next_pipe[0])
					linux.close(next_pipe[1])
				}

				if args[0] == "cd" || args[0] == "exit" {
					exit(0)
				}

				run_cmd(args[0], args[1:])
				exit(0)
			} else {
				if prev_read_end != 0 do linux.close(prev_read_end)
				if !is_last {
					linux.close(next_pipe[1])
					prev_read_end = next_pipe[0]
				}

				if is_last {
					linux.waitpid(pid, nil, {}, nil)
				}
			}
		}
	} else {
		args := fields(input, context.temp_allocator)
		args = expand_env(args[:])
		switch args[0] {
		case "cd":
			target: string
			if len(args) == 1 do target = get_homedir()
			else if len(args) == 2 do target = expand_tilde(args[1])
			set_cwd(target)
		case "exit":
			exit(0)
		case "echo":
			write(1, join(args[1:], " "))
			write(1, "\n")
		case:
			run_cmd(args[0], args[1:])
		}
	}
}

print_prompt :: proc(username, hostname, cwd: string) {
	write(1, username)
	write(1, "@")
	write(1, hostname)
	write(1, " ")
	write(1, shorten_home(get_cwd()))
	write(1, " $ ")
}


main :: proc() {
	username := get_env("USER")
	hostname := get_env("HOSTNAME")

	for {
		print_prompt(username, hostname, get_cwd())

		line, ok := read_line(buffer[:])

		if !ok {
			exit(0)
		}

		if len(line) > 0 {
			exec(line)
		}

		free_all(context.temp_allocator)
	}
}
