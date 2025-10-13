module main


$if windows {
	$compile_error('Subprocess only works on Windows')
}

import strings

#include <fcntl.h>

fn C.WriteFile(hFile voidptr, lpBuffer voidptr, nNumberOfBytesToWrite u32, lpNumberOfBytesWritten &u32, lpOverlapped voidptr) bool
fn C.CreateProcess(lpApplicationName &u16, lpCommandLine &u16, lpProcessAttributes voidptr, lpThreadAttributes voidptr, bInheritHandles bool, dwCreationFlags u32, lpEnvironment voidptr, lpCurrentDirectory &u16, lpStartupInfo voidptr, lpProcessInformation voidptr) bool
fn C.CreateJobObject(lpJobAttributes voidptr, lpName &u16) voidptr
fn C.SetInformationJobObject(hJob voidptr, JobObjectInformationClass u32, lpJobObjectInformation voidptr, cbJobObjectInformationLength u32) bool
fn C.AssignProcessToJobObject(hJob voidptr, hProcess voidptr) bool
fn C.CreateIoCompletionPort(lpFileHandle voidptr, hFilePort voidptr, dwThreadId u64, dwNumberOfConcurrentThreads u32) voidptr
fn C.GetQueuedCompletionStatus(hFilePort voidptr, lpNumberOfBytesTransferred &u32, lpCompletionKey &usize, lpOverlapped &voidptr, dwMilliseconds u32) bool
fn C.ResumeThread(hThread voidptr) u32

fn eprintln_exit(message string) {
	eprintln(message)
	exit(1)
}

struct ProcessInformation {
mut:
	h_process     voidptr
	h_thread      voidptr
	dw_process_id u32
	dw_thread_id  u32
}

struct StartupInfo {
mut:
	cb                 u32
	lp_reserved        &u16 = unsafe { nil }
	lp_desktop         &u16 = unsafe { nil }
	lp_title           &u16 = unsafe { nil }
	dw_x               u32
	dw_y               u32
	dw_x_size          u32
	dw_y_size          u32
	dw_x_count_chars   u32
	dw_y_count_chars   u32
	dw_fill_attributes u32
	dw_flags           u32
	w_show_window      u16
	cb_reserved2       u16
	lp_reserved2       &u8 = unsafe { nil }
	h_std_input        voidptr
	h_std_output       voidptr
	h_std_error        voidptr
}

struct SecurityAttributes {
mut:
	n_length               u32
	lp_security_descriptor voidptr
	b_inherit_handle       bool
}

struct IOCounters {
	read_operation_count  u64
	write_operation_count u64
	other_operation_count u64
	read_transfer_count   u64
	write_transfer_count  u64
	other_transfer_count  u64
}

struct JobObjectExtendedLimitInformation {
	basic_limit_information  JobObjectBasicLimitInformation
	io_info                  IOCounters
	process_memory_limit     u64
	job_memory_limit         u64
	peak_process_memory_used u64
	peak_job_memory_used     u64
}

struct JobObjectBasicLimitInformation {
	per_process_user_time_limit u64
	per_job_user_time_limit     u64
	limit_flags                 u32
	minimum_working_set_size    u64
	maximum_working_set_size    u64
	active_process_limit        u32
	affinity                    u64
	priority_class              u32
	scheduling_class            u32
}

struct JobObjectAssociateCompletionPort {
	completion_key  voidptr
	completion_port voidptr
}

enum Handler as u8 {
	pipe
	inherit
}

struct StdIterator {
	pipe &u32
mut:
	idx int
	e   Execute
}

fn (mut iter StdIterator) next() ?string {
	if iter.e.ended {
		return none
	}

	defer { iter.idx++ }

	buf := [4096]u8{}
	mut bytes_read := u32(0)
	mut read_data := strings.new_builder(1024)

	unsafe {
		result := C.ReadFile(iter.pipe, &buf[0], 4096, voidptr(&bytes_read), 0)
		read_data.write_ptr(&buf[0], int(bytes_read))

		if result == false {
			return none
		}
	}
	mut linesep := ''

	$if windows {
		linesep = '\r\n'
	} $else {
		linesep = '\n'
	}

	mut s := read_data.str()
	if s.ends_with(linesep) {
		return s[..s.len - linesep.len]
	}

	return s
}

struct Execute {
	command string
	stdin   Handler = .inherit
	stdout  Handler = .inherit
	stderr  Handler = .inherit

	stdin_read  &u32 = &u32(unsafe { nil })
	stdout_read &u32 = &u32(unsafe { nil })
	stderr_read &u32 = &u32(unsafe { nil })

	stdin_write  &u32 = &u32(unsafe { nil })
	stdout_write &u32 = &u32(unsafe { nil })
	stderr_write &u32 = &u32(unsafe { nil })

	pi ProcessInformation = ProcessInformation{}
mut:
	exit_code u32
	ended     bool

	io_port voidptr
	h_job  voidptr
}

// https://learn.microsoft.com/en-us/windows/win32/procthread/creating-a-child-process-with-redirected-input-and-output
// https://github.com/python/cpython/blob/main/Lib/subprocess.py#L1348
fn (mut e Execute) run() {
	// Input and output objects. The general principle is like this:
	//
	// Parent                   Child
	// ------                   -----
	// p2cwrite   ---stdin--->  p2cread
	// c2pread    <--stdout---  c2pwrite
	// errread    <--stderr---  errwrite

	sa := SecurityAttributes{
		n_length:         sizeof(C.SECURITY_ATTRIBUTES)
		b_inherit_handle: true
	}

	if e.stdin == .pipe {
		if !C.CreatePipe(voidptr(&e.stdin_read), voidptr(&e.stdin_write), voidptr(&sa),
			0) {
			eprintln_exit('stdin CreatePipe failed (${C.GetLastError()}).')
		}

		if !C.SetHandleInformation(e.stdin_write, C.HANDLE_FLAG_INHERIT, 0) {
			eprintln_exit('stdin SetHandleInformation failed (${C.GetLastError()}).')
		}
	}

	if e.stdout == .pipe {
		if !C.CreatePipe(voidptr(&e.stdout_read), voidptr(&e.stdout_write), voidptr(&sa),
			0) {
			eprintln_exit('stdout CreatePipe failed (${C.GetLastError()}).')
		}

		if !C.SetHandleInformation(e.stdout_read, C.HANDLE_FLAG_INHERIT, 0) {
			eprintln_exit('stdout SetHandleInformation failed (${C.GetLastError()}).')
		}
	}

	if e.stderr == .pipe {
		if !C.CreatePipe(voidptr(&e.stderr_read), voidptr(&e.stderr_write), voidptr(&sa),
			0) {
			eprintln_exit('stderr CreatePipe failed (${C.GetLastError()}).')
		}

		if !C.SetHandleInformation(e.stderr_read, C.HANDLE_FLAG_INHERIT, 0) {
			eprintln_exit('stderr SetHandleInformation failed (${C.GetLastError()}).')
		}
	}

	si := StartupInfo{
		cb:           sizeof(StartupInfo)
		dw_flags:     u32(C.STARTF_USESTDHANDLES)
		h_std_input:  e.stdin_read
		h_std_output: e.stdout_write
		h_std_error:  e.stderr_write
	}

	if !C.CreateProcess(0, e.command.to_wide(), 0, 0, C.TRUE, C.CREATE_NO_WINDOW | C.CREATE_SUSPENDED, 0, 0,
		voidptr(&si), voidptr(&e.pi)) {
		eprintln_exit('CreateProcess failed (${C.GetLastError()}).')
	}

	// Kill child when parent dies
	e.h_job = C.CreateJobObject(0, 0)

	info := JobObjectExtendedLimitInformation{
		basic_limit_information: JobObjectBasicLimitInformation{
			limit_flags: u32(C.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
		}
	}

	e.io_port = C.CreateIoCompletionPort(C.INVALID_HANDLE_VALUE, 0, 0, 1)

	port := JobObjectAssociateCompletionPort{
		completion_key:  e.h_job
		completion_port: e.io_port
	}

	if !C.SetInformationJobObject(e.h_job, C.JobObjectExtendedLimitInformation, voidptr(&info),
		sizeof(JobObjectExtendedLimitInformation)) {
		eprintln_exit('SetInformationJobObject KILL failed (${C.GetLastError()}).')
	}
	if !C.SetInformationJobObject(e.h_job, C.JobObjectAssociateCompletionPortInformation,
		voidptr(&port), sizeof(JobObjectAssociateCompletionPort)) {
		eprintln_exit('SetInformationJobObject WAIT failed (${C.GetLastError()}).')
	}

	if !C.AssignProcessToJobObject(e.h_job, e.pi.h_process) {
		eprintln_exit('AssignProcessToJobObject failed (${C.GetLastError()}).')
	}

	C.ResumeThread(e.pi.h_thread)
	C.CloseHandle(e.stdin_read)
	C.CloseHandle(e.stdout_write)
	C.CloseHandle(e.stderr_write)
	C.CloseHandle(e.pi.h_thread)
}

fn (mut e Execute) wait() u32 {
	exit_code := u32(0)

	C.WaitForSingleObject(e.pi.h_process, C.INFINITE)

	// TODO: Wait for the subprocess's children to end, instead of waiting only for the subprocess to end
	//
	// for {
	// 	mut message := u32(0)
	// 	mut completion_key := usize(0)
	// 	mut overlapped := voidptr(0)

	// 	if !C.GetQueuedCompletionStatus(e.io_port, &message, &completion_key, &overlapped, C.INFINITE) {
	// 		eprintln_exit('GetQueuedCompletionStatus failed (${C.GetLastError()}).')
	// 	}

	// 	println('$message, ${C.JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO}, ${message == C.JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO}')
	// 	if completion_key == e.h_job && message == C.JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO {
	// 		println('a')
	// 		break
	// 	}
	// }
	// println('done')

	C.GetExitCodeProcess(e.pi.h_process, voidptr(&exit_code))

	e.exit_code = exit_code
	e.ended = true

	return exit_code
}

fn (e Execute) stdin_write(s string) {
	if !C.WriteFile(e.stdin_write, s.str, s.len, &u32(unsafe { nil }), 0) {
		eprintln_exit('WriteFile failed (${C.GetLastError()}).')
	}
}

fn (e Execute) stderr_iter() StdIterator {
	return StdIterator{
		pipe: e.stderr_read
		e:    e
	}
}

fn (e Execute) stdout_iter() StdIterator {
	return StdIterator{
		pipe: e.stdout_read
		e:    e
	}
}

fn (e Execute) stderr_read() string {
	mut s := ''

	for si in e.stderr_iter() {
		s += si
	}

	return s
}

fn (e Execute) stdout_read() string {
	mut s := ''

	for si in e.stdout_iter() {
		s += si
	}

	return s
}
