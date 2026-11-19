open Eio.Std
module Process = Eio_posix.Low_level.Process
module Trace = Eio.Private.Trace
module Fd = Eio_unix.Fd
module Rcfd = Eio_unix.Private.Rcfd
module Fork_action = Eio_unix.Private.Fork_action

type mode = R | RW
type yes = Yes
type no = No
type uns_map = (int * int * int) list

type 'a config = {
  args : (executor * string list) option;
  rootfs : (string * bool * mode) option;
  mounts : mount list;
  network : network;
  uid_map : uns_map;
  gid_map : uns_map;
  extra_actions : Eio_unix.Private.Fork_action.t list;
}

and mount = { src : string; tgt : string; mode : int [@warning "-69"] }
and network = { devices : string list }
and executor = Program of string | File of Eio_unix.Fd.t

(* Actions for namespacing *)
module Mount = struct
  module Flags = struct
    include Config.Mount_flags

    let empty : t = 0
    let ( + ) = ( lor )
  end

  module Types = struct
    type t = string

    let btrfs = "btrfs"
    let ext4 = "ext4"
    let auto = "auto"
  end
end

let make_mount ~src ~tgt ~mode =
  let mode = if mode = R then Mount.Flags.ms_rdonly else Mount.Flags.empty in
  { src; tgt; mode }

external action_mount : unit -> Fork_action.fork_fn = "void_fork_mount"

let action_mount = action_mount ()

let _mount ~(src : string) ~(target : string) (type_ : Mount.Types.t)
    (flags : Mount.Flags.t) =
  Fork_action.
    { run = (fun k -> k (Obj.repr (action_mount, src, target, type_, flags))) }

external action_pivot_root : unit -> Fork_action.fork_fn
  = "void_fork_pivot_root"

let action_pivot_root = action_pivot_root ()

let pivot_root (new_root : string) (new_root_flags : Mount.Flags.t)
    (tmpfs : bool) (mounts : mount list) =
  Fork_action.
    {
      run =
        (fun k ->
          k
            (Obj.repr
               (action_pivot_root, new_root, new_root_flags, tmpfs, mounts)));
    }

external action_pause : unit -> Fork_action.fork_fn = "void_fork_pause"

let action_pause = action_pause ()

let pause (fd : Unix.file_descr) =
  Fork_action.{ run = (fun k -> k (Obj.repr (action_pause, fd))) }

external action_fexecve : unit -> Fork_action.fork_fn = "void_fork_fexecve"

type c_array

external make_string_array : int -> c_array = "eio_unix_make_string_array"

let action_fexecve = action_fexecve ()

let fexecve fd ~argv ~env =
  let argv_c_array = make_string_array (Array.length argv) in
  let env_c_array = make_string_array (Array.length env) in
  Fork_action.
    {
      run =
        (fun k ->
          k
            (Obj.repr
               (action_fexecve, fd, argv_c_array, argv, env_c_array, env)));
    }

module Flags = struct
  include Config.Clone_flags

  let ( + ) = ( lor )
end

external eio_spawn :
  Unix.file_descr ->
  Flags.t ->
  Eio_unix.Private.Fork_action.c_action list ->
  int * Unix.file_descr = "caml_void_clone3"

external eio_fork :
  Unix.file_descr ->
  Flags.t ->
  Eio_unix.Private.Fork_action.c_action list ->
  int * Unix.file_descr = "caml_void_fork"

type t = {
  pid : int;
  pid_fd : Fd.t;
  exit_status : Unix.process_status Promise.t;
}

let exit_status t = t.exit_status
let pid t = t.pid

(* Read a (typically short) error message from a child process. *)
let rec read_response fd =
  let buf = Cstruct.create 256 in
  match Eio_posix.Low_level.readv fd [| buf |] with
  | 0 | (exception End_of_file) -> ""
  | len -> Cstruct.to_string buf ~len ^ read_response fd

let void_flags = List.fold_left Flags.( + ) 0 Flags.all

type path = string

let empty =
  {
    args = None;
    rootfs = None;
    mounts = [];
    network = { devices = [] };
    extra_actions = [];
    uid_map = [];
    gid_map = [];
  }

let std_fds =
  [
    (0, Eio_unix.Fd.stdin, `Blocking);
    (1, Eio_unix.Fd.stdout, `Blocking);
    (2, Eio_unix.Fd.stderr, `Blocking);
  ]

let configure_user_namespace ~process_mgr ~pid uids gids =
  let uid_cmd =
    [ "newuidmap"; string_of_int pid ]
    @ List.concat_map
        (fun (container, host, len) ->
          [ string_of_int container; string_of_int host; string_of_int len ])
        uids
  in
  let () = Eio.Process.run process_mgr uid_cmd in
  let gid_cmd =
    [ "newgidmap"; string_of_int pid ]
    @ List.concat_map
        (fun (container, host, len) ->
          [ string_of_int container; string_of_int host; string_of_int len ])
        gids
  in
  let () = Eio.Process.run process_mgr gid_cmd in
  ()

let actions ~pause v : Fork_action.t list =
  let root, tmpfs, root_mode =
    match v.rootfs with
    | None -> (Filename.temp_dir "void-" "-tmpdir", true, R)
    | Some (s, b, m) -> (s, b, m)
  in
  let e =
    match v.args with
    | None -> []
    | Some (program, args) -> (
        match program with
        | Program p ->
            [
              Process.Fork_action.execve p ~env:[||] ~argv:(Array.of_list args);
            ]
        | File fd ->
            Eio_unix.Fd.use_exn "fexec" fd @@ fun ufd ->
            [ fexecve ufd ~env:[||] ~argv:(Array.of_list args) ])
  in
  let e = v.extra_actions @ e in
  let fds_to_map = match v.args with Some (File fd, _) -> [ fd ] | _ -> [] in
  let fds =
    List.map
      (fun fd ->
        let fd_int : int = Eio_unix.Fd.use_exn "inherit-fds" fd Obj.magic in
        (fd_int, fd, `Nonblocking))
      fds_to_map
    |> List.append std_fds |> Eio_unix.Private.Fork_action.inherit_fds
  in
  (* Process mount point points *)
  let mounts =
    List.map
      (fun mnt ->
        let src = Filename.concat "/.old_root" mnt.src in
        let tgt = Filename.concat "/" mnt.tgt in
        { mnt with tgt; src })
      v.mounts
  in
  let root_flags =
    if root_mode = R then Mount.Flags.ms_rdonly else Mount.Flags.empty
  in
  let mounts = pivot_root root root_flags tmpfs mounts in
  [ mounts; fds ] @ pause @ e

let rootfs ~mode path v = { v with rootfs = Some (path, false, mode) }

let tmp_rootfs ~mode v =
  let tmpdir = Filename.temp_dir "void-" "-tmpdir" in
  { v with rootfs = Some (tmpdir, true, mode) }

let exec args v = { v with args = Some (Program (List.hd args), args) }

let fexec file args v =
  match Eio_unix.Resource.fd_opt file with
  | None -> invalid_arg "No underlying file descriptor"
  | Some fd -> { v with args = Some (File fd, "fexec" :: args) }

let mount mount v = { v with mounts = mount :: v.mounts }

let network device v =
  { v with network = { devices = device :: v.network.devices } }

let fork_actions actions v =
  { v with extra_actions = actions @ v.extra_actions }

let uid_map uid_map v = { v with uid_map = uid_map @ v.uid_map }
let gid_map gid_map v = { v with gid_map = gid_map @ v.gid_map }

let read_subs ~username path =
  Eio.Path.load path |> String.split_on_char '\n'
  |> List.map (String.split_on_char ':')
  |> List.find_map (function
    | user :: start :: [ len ] when String.equal user username ->
        Some (int_of_string start, int_of_string len)
    | _ -> None)

let default_maps ~subuid ~subgid =
  let uid, gid, username =
    match (Unix.getuid (), Unix.getgid ()) with
    | 0, _ -> Fmt.invalid_arg "default_maps: cannot be run as root"
    | n, m -> (n, m, (Unix.getpwuid n).pw_name)
  in
  let subuid =
    read_subs ~username subuid
    |> Option.map (fun (s, len) -> [ (1, s, len) ])
    |> Option.value ~default:[]
  in
  let subgid =
    read_subs ~username subgid
    |> Option.map (fun (s, len) -> [ (1, s, len) ])
    |> Option.value ~default:[]
  in
  let root_uid = (0, uid, 1) in
  let root_gid = (0, gid, 1) in
  (root_uid :: subuid, root_gid :: subgid)

(* From eio_linux/eio_posix *)
let with_pipe fn =
  Switch.run @@ fun sw ->
  let r, w = Eio_posix.Low_level.pipe ~sw in
  fn r w

external pidfd_send_signal : Unix.file_descr -> int -> unit
  = "caml_void_pidfd_send_signal"

let signal t signum =
  Fd.use t.pid_fd ~if_closed:Fun.id @@ fun pid_fd ->
  pidfd_send_signal pid_fd signum

let rec waitpid pid =
  match Unix.waitpid [] pid with
  | p, status ->
      assert (p = pid);
      status
  | exception Unix.Unix_error (EINTR, _, _) -> waitpid pid

let need_pause v = v.uid_map <> [] || v.gid_map <> []

let handle_pause ~process_mgr v pid =
  configure_user_namespace ~process_mgr ~pid v.uid_map v.gid_map

let write_once_and_cleanup fd =
  Fun.protect ~finally:(fun () -> Unix.close fd) @@ fun () ->
  assert (Unix.write fd (Bytes.of_string "!") 0 1 = 1)

let spawn ~process_mgr ~sw v =
  with_pipe @@ fun errors_r errors_w ->
  let pause_r, pause_w = Unix.pipe ~cloexec:true () in
  let pause = if need_pause v then [ pause pause_r ] else [] in
  Eio_unix.Private.Fork_action.with_actions (actions ~pause v)
  @@ fun c_actions ->
  Switch.check sw;
  let exit_status, set_exit_status = Promise.create () in
  let t =
    let pid, pid_fd =
      Fd.use_exn "errors-w" errors_w @@ fun errors_w ->
      Eio.Private.Trace.with_span "spawn" @@ fun () ->
      let flags = Flags.(clone_pidfd + void_flags) in
      eio_spawn errors_w flags c_actions
    in
    if need_pause v then begin
      handle_pause ~process_mgr v pid;
      write_once_and_cleanup pause_w
    end;
    let pid_fd = Fd.of_unix ~sw ~seekable:false ~close_unix:true pid_fd in
    { pid; pid_fd; exit_status }
  in
  Fd.close errors_w;
  Fiber.fork_daemon ~sw (fun () ->
      let cleanup () =
        Fd.close t.pid_fd;
        Promise.resolve set_exit_status (waitpid t.pid);
        `Stop_daemon
      in
      match Eio_posix.Low_level.await_readable "void_spawn" t.pid_fd with
      | () -> Eio.Cancel.protect cleanup
      | exception Eio.Cancel.Cancelled _ ->
          Eio.Cancel.protect (fun () ->
              signal t Sys.sigkill;
              Eio_posix.Low_level.await_readable "void_spawn" t.pid_fd;
              cleanup ()));
  (* Check for errors starting the process. *)
  match read_response errors_r with
  | "" -> t (* Success! Execing the child closed [errors_w] and we got EOF. *)
  | err -> failwith err

let spawn_hermetic ~process_mgr ~sw v = spawn ~process_mgr ~sw v

let to_eio_status t =
  match t with
  | Unix.WEXITED i -> `Exited i
  | Unix.WSIGNALED i -> `Signaled i
  | Unix.WSTOPPED _ -> assert false

let pp_exit_status ppf = function
  | Unix.WEXITED n -> Fmt.pf ppf "Exited with %i" n
  | Unix.WSTOPPED n -> Fmt.pf ppf "Stopped with %i" n
  | Unix.WSIGNALED n -> Fmt.pf ppf "Signalled with %i" n

let run ~process_mgr t =
  Eio.Switch.run @@ fun sw ->
  spawn ~sw ~process_mgr t |> exit_status |> Eio.Promise.await

module Private = struct
  module Fork_actions = struct
    let pivot_root ?(mounts = []) ~root root_mode =
      let root_flags =
        if root_mode = R then Mount.Flags.ms_rdonly else Mount.Flags.empty
      in
      pivot_root root root_flags false mounts

    let configure_user_namespace = configure_user_namespace
  end

  let read_all fd =
    let buf = Buffer.create 16 in
    let bs = Bytes.create 16 in
    Eio_unix.Fd.use_exn "read_all" fd @@ fun fd ->
    let rec loop () =
      match Unix.read fd bs 0 16 with
      | 0 | (exception End_of_file) -> Buffer.contents buf
      | exception Unix.Unix_error (Unix.EAGAIN, _, _) -> loop ()
      | n ->
          Buffer.add_bytes buf (Bytes.sub bs 0 n);
          loop ()
    in
    loop ()

  let fork_actions actions =
    let actions = actions in
    with_pipe @@ fun errors_r errors_w ->
    Eio_unix.Private.Fork_action.with_actions actions @@ fun c_actions ->
    let pid, pid_fd =
      Fd.use_exn "errors-w" errors_w @@ fun errors_w ->
      Eio.Private.Trace.with_span "fork_actions" @@ fun () ->
      let flags = Flags.(clone_pidfd + void_flags) in
      eio_fork errors_w flags c_actions
    in
    match pid with
    | 0 -> (pid, pid_fd)
    | _ -> (
        Fd.close errors_w;
        match read_all errors_r with
        | "" -> (pid, pid_fd)
        | msg -> Fmt.failwith "fork actions failed: %s" msg)
end
