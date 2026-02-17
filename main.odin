package main

is_space :: #force_inline proc(c: u8) -> bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f'
}


buffer := []u8{}
buffer_ptr := 0
line_buffer := []u8{}
env_buffer := []u8{}
env_len := 0
exit_code := 0

foreign _ {
	@(link_name = "asm_exit")
	exit :: proc(code: i32) -> ! ---
	@(link_name = "asm_write")
	write :: proc(fd: i32, s: string) ---
	@(link_name = "asm_read")
	read :: proc(fd: i32, buffer_ptr: [^]u8, buffer_len: int) -> int ---
	@(link_name = "asm_close")
	close :: proc(fd: i32) -> i32 ---
	@(link_name = "asm_mmap")
	mmap :: proc(addr: rawptr, size: uint, prot: i32, flags: i32, fd: i32, offset: i64) -> rawptr ---
	@(link_name = "asm_mremap")
	mremap :: proc(old_addr: rawptr, old_size: uint, new_size: uint, flags: i32) -> rawptr ---
	@(link_name = "asm_open")
	open :: proc(dirfd: i32, path: cstring, flags: i32, mode: i32) -> i32 ---
	@(link_name = "asm_pipe")
	pipe :: proc(fds: ^[2]i32) -> i32 ---
	@(link_name = "asm_dup2")
	dup2 :: proc(old_fd, new_fd: i32) -> i32 ---
	@(link_name = "asm_execveat")
	execveat :: proc(dirfd: i32, pathname: cstring, argv: [^]cstring, envp: [^]cstring, flags: i32) -> i32 ---
	@(link_name = "asm_getcwd")
	getcwd :: proc(buf: [^]u8, size: int) -> int ---
	@(link_name = "asm_fork")
	fork :: proc() -> i32 ---
	@(link_name = "asm_wait4")
	wait4 :: proc(pid: i32, status: ^i32, options: i32, rusage: rawptr) -> i32 ---
	@(link_name = "asm_chdir")
	chdir :: proc(path: cstring) -> i32 ---
	@(link_name = "asm_faccessat")
	faccessat :: proc(dirfd: i32, pathname: cstring, mode: i32, flags: i32) -> i32 ---
	@(link_name = "asm_to_cstring")
	_to_cstring :: proc(dest: [^]u8, src: rawptr, len: int) -> cstring ---
	@(link_name = "asm_join")
	_join :: proc(dest: [^]u8, strings_ptr: [^]string, count: int, sep_ptr: [^]u8, sep_len: int) -> int ---
}

copy :: proc(dst, src: rawptr, len: int) {
	d := ([^]u8)(dst)
	s := ([^]u8)(src)
	for i in 0 ..< len {
		d[i] = s[i]
	}
}

to_cstring :: proc(s: string) -> cstring {
	if len(s) == 0 do return ""
	mem := scratch_alloc(len(s) + 1)
	return _to_cstring(raw_data(mem), raw_data(s), len(s))
}

join :: proc(a: []string, sep: string) -> string {
	if len(a) == 0 do return ""
	if len(a) == 1 do return a[0]
	total_len := len(sep) * (len(a) - 1)
	for s in a do total_len += len(s)

	mem := scratch_alloc(total_len)
	_join(raw_data(mem), raw_data(a), len(a), raw_data(sep), len(sep))
	return string(mem)
}

slice_alloc :: proc(size: int) -> []u8 {
	addr := mmap(nil, uint(size), 0x1 | 0x2, 0x02 | 0x20, -1, 0)

	if uintptr(addr) >= ~uintptr(4095) {
		write(2, "mmap failed\n")
		exit(1)
	}

	return ([^]u8)(addr)[:size]
}

slice_grow :: proc(old_slice: []u8, new_size: int) -> []u8 {
	new_addr := mremap(raw_data(old_slice), uint(len(old_slice)), uint(new_size), 1)

	if uintptr(new_addr) >= ~uintptr(4095) {
		write(2, "mremap failed\n")
		exit(1)
	}
	return ([^]u8)(new_addr)[:new_size]
}

scratch_alloc :: proc(size: int) -> []u8 {
	if buffer_ptr + size > len(buffer) {
		write(2, "Error: global buffer exhausted\n")
		exit(1)
	}
	res := buffer[buffer_ptr:buffer_ptr + size]
	buffer_ptr += size
	return res
}

init_env :: proc() {
	path_cstr := to_cstring("/proc/self/environ")
	fd := open(-100, path_cstr, 0, 0)
	if fd < 0 do return

	n := read(fd, raw_data(env_buffer), len(env_buffer))
	env_len = n
	close(fd)
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
	full_entry := join({key, "=", val}, "")
	entry_len := len(full_entry)

	cursor := 0
	for cursor < env_len {
		start := cursor
		end := start
		for end < env_len && env_buffer[end] != 0 {end += 1}

		entry := string(env_buffer[start:end])

		if len(entry) > len(key) && entry[len(key)] == '=' && entry[:len(key)] == key {
			if entry_len <= len(entry) {
				copy(raw_data(env_buffer[start:]), raw_data(full_entry), len(full_entry))
				if entry_len < len(entry) {
					for i in entry_len ..< len(entry) {env_buffer[start + i] = 0}
				}
				return
			}
			env_buffer[start] = 0
			break
		}
		cursor = end + 1
	}

	if env_len + entry_len + 1 <= len(env_buffer) {
		copy(raw_data(env_buffer[env_len:]), raw_data(full_entry), len(full_entry))
		env_len += entry_len
		env_buffer[env_len] = 0
		env_len += 1
	} else {
		write(2, "Error: env_buffer is full\n")
	}
}

is_executable :: proc(path: cstring) -> bool {
	return faccessat(-100, path, 1, 0) == 0
}

find_path :: proc(cmd: string) -> cstring {
	if contains(cmd, "/") {
		return to_cstring(cmd)
	}
	path_env := get_env("PATH")
	if path_env == "" do path_env = "/usr/bin:/bin"
	directories := split(path_env, ':')
	for dir in directories {
		if len(dir) == 0 do continue
		full_path := join({dir, "/", cmd}, "")
		c_path := to_cstring(full_path)
		if is_executable(c_path) {
			return c_path
		}
	}
	return to_cstring(cmd)
}

read_line :: proc(buf: ^[]u8) -> (string, bool) {
	total_read := 0

	for {
		if total_read >= len(buf^) {
			new_size := len(buf^) + 4096
			if new_size == 0 do new_size = 4096
			buf^ = slice_grow(buf^, new_size)
		}
		b: u8
		n := read(0, &b, 1)

		if n <= 0 {
			if total_read == 0 do return "", false
			break
		}

		if b == '\n' {
			break
		}

		buf^[total_read] = b
		total_read += 1
	}

	return string(buf^[:total_read]), true
}

itoa :: proc(n: int) -> string {
	if n == 0 {
		mem := scratch_alloc(1)
		mem[0] = '0'
		return string(mem)
	}

	val := n
	is_negative := false
	if val < 0 {
		is_negative = true
		val = -val
	}

	length := 0
	temp := val
	for temp > 0 {
		temp /= 10
		length += 1
	}
	if is_negative do length += 1

	mem := scratch_alloc(length)

	curr := length - 1
	temp_val := val
	for temp_val > 0 {
		mem[curr] = u8(temp_val % 10) + '0'
		temp_val /= 10
		curr -= 1
	}

	if is_negative {
		mem[0] = '-'
	}

	return string(mem)
}

split :: proc(s: string, char: byte) -> []string {
	if len(s) == 0 do return nil

	n := 1
	for i in 0 ..< len(s) {
		if s[i] == char do n += 1
	}

	mem := scratch_alloc(n * size_of(string))
	res := ([^]string)(raw_data(mem))[:n]

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

trim_space :: proc(s: string) -> string {
	if len(s) == 0 do return ""

	start := 0
	if start < len(s) && is_space(s[start]) {
		start += 1
	}

	if start == len(s) do return ""

	end := len(s)
	for end > start && is_space(s[end - 1]) {
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

fields :: proc(s: string) -> []string {
	if len(s) == 0 do return nil
	n := 0
	in_field := false
	for i in 0 ..< len(s) {
		is_sp := is_space(s[i])
		if !is_sp && !in_field {
			in_field = true; n += 1
		} else if is_sp {
			in_field = false
		}
	}
	if n == 0 do return nil

	mem := scratch_alloc(n * size_of(string))
	res := ([^]string)(raw_data(mem))[:n]

	na := 0
	field_start := -1
	for i in 0 ..< len(s) {
		if !is_space(s[i]) {
			if field_start == -1 do field_start = i
		} else if field_start != -1 {
			res[na] = s[field_start:i]
			na += 1; field_start = -1
		}
	}
	if field_start != -1 do res[na] = s[field_start:]
	return res
}

concatenate :: proc(a: []string) -> string {
	if len(a) == 0 do return ""

	total_len := 0
	for s in a do total_len += len(s)

	mem := scratch_alloc(total_len)

	offset := 0
	for s in a {
		copy(raw_data(mem[offset:]), raw_data(s), len(s))
		offset += len(s)
	}
	return string(mem)
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
	n := getcwd(raw_data(buffer[:]), len(buffer))
	return string(buffer[:n])
}

set_cwd :: proc(path: string) -> bool {
	cpath := to_cstring(path)

	errno := chdir(cpath)
	return errno == 0
}


shorten_home :: proc(path: string) -> string {
	home := get_homedir()

	if path == home {
		return "~"
	}

	if has_prefix(path, home) {
		return concatenate({"~", path[len(home):]})
	}

	return path
}

expand_tilde :: proc(input: string) -> string {
	home := get_homedir()
	if input == "~" {
		return home
	}
	if has_prefix(input, "~/") {
		return concatenate({home, input[1:]})
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

run_cmd :: proc(prog: string, args: []string, is_forked := false) {
	argv: [128]cstring
	argv[0] = find_path(prog)

	arg_count := 1
	out_file: string
	append_mode := false

	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		if arg == ">" || arg == ">>" {
			if i + 1 < len(args) {
				out_file = args[i + 1]
				append_mode = (arg == ">>")
				break
			}
		}

		if arg_count < 127 {
			argv[arg_count] = to_cstring(arg)
			arg_count += 1
		}
	}
	argv[arg_count] = nil

	execute_internal :: proc(path: cstring, argv: [^]cstring, out_file: string, append: bool) {
		if out_file != "" {
			O_WRONLY: i32 : 1
			O_CREAT: i32 : 64
			O_TRUNC: i32 : 512
			O_APPEND: i32 : 1024

			flags := O_WRONLY | O_CREAT
			flags |= append ? O_APPEND : O_TRUNC

			fd := open(-100, to_cstring(out_file), flags, 0o644)
			if fd >= 0 {
				dup2(fd, 1)
				close(fd)
			}
		}
		execveat(-100, path, argv, nil, 0)
		exit(127)
	}

	if is_forked {
		execute_internal(argv[0], raw_data(argv[:]), out_file, append_mode)
	} else {
		pid := fork()
		if pid == 0 {
			execute_internal(argv[0], raw_data(argv[:]), out_file, append_mode)
		} else {
			wait4(pid, nil, {}, nil)
		}
	}
}

exec :: proc(input: string) {
	input := trim_space(input)
	if len(input) == 0 {return}

	if contains(input, "|") {
		commands := split(input, '|')
		prev_read_end: i32 = 0

		for i in 0 ..< len(commands) {
			cmd_str := trim_space(commands[i])
			args := fields(cmd_str)
			args = expand_env(args[:])

			is_last := i == len(commands) - 1
			next_pipe: [2]i32

			if !is_last {
				pipe(&next_pipe)
			}

			pid := fork()
			if pid == 0 {
				if prev_read_end != 0 {
					dup2(prev_read_end, 0)
					close(prev_read_end)
				}

				if !is_last {
					close(next_pipe[0])
					dup2(next_pipe[1], 1)
					close(next_pipe[1])
				}

				if args[0] == "cd" || args[0] == "exit" {
					exit(0)
				}

				run_cmd(args[0], args[1:], true)
				exit(0)
			} else {
				if prev_read_end != 0 do close(i32(prev_read_end))
				if !is_last {
					close(i32(next_pipe[1]))
					prev_read_end = next_pipe[0]
				}

				if is_last {
					wait4(pid, nil, {}, nil)
				}
			}
		}
	} else {
		args := fields(input)
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
	// Increase this to 64KB or more since all work happens here now
	buffer = slice_alloc(65536)
	line_buffer = slice_alloc(4096)
	env_buffer = slice_alloc(4096)

	init_env()
	for {
		buffer_ptr = 0

		username := get_env("USER")
		hostname := get_env("HOSTNAME")
		print_prompt(username, hostname, get_cwd())

		line, ok := read_line(&line_buffer)
		if !ok do exit(0)

		if len(line) > 0 {
			exec(line)
		}
	}
}
