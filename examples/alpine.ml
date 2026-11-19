open Eio.Std

let test_data fs data =
  let tempdir = Filename.temp_dir "void-" "-alpine" in
  Eio.Path.(save ~create:(`If_missing 0o644) (fs / tempdir / "data.txt") data);
  Eio.traceln "Test data in %s" tempdir;
  tempdir

let fork_example ~alpine_img =
  let open Void.Private in
  let std_fds =
    [
      (0, Eio_unix.Fd.stdin, `Blocking);
      (1, Eio_unix.Fd.stdout, `Blocking);
      (2, Eio_unix.Fd.stderr, `Blocking);
    ]
  in
  match
    fork_actions
      [
        Fork_actions.pivot_root ~root:alpine_img R;
        Eio_unix.Private.Fork_action.inherit_fds std_fds;
      ]
  with
  | 0, _ ->
      let i = Sys.command "/bin/ls -la /" in
      exit i
  | pid, _ -> (
      Eio.traceln "PID of child %i%!" pid;
      match Unix.waitpid [] pid with
      | _, Unix.WEXITED e -> Fmt.pr "Exited with %i\n%!" e
      | _ -> assert false)

(* This example read-only mounts a copy of busybox
   into the root-filesystem of the process. *)
let () =
  Eio_posix.run @@ fun env ->
  Switch.run @@ fun sw ->
  let fs = env#fs in
  let proc = env#process_mgr in
  let alpine_img = Image.get_image ~fs ~proc "alpine" in
  let arg = try Some Sys.argv.(1) with _ -> None in
  match arg with
  | Some "fork" -> fork_example ~alpine_img
  | _ ->
      let mount_src = test_data fs "Hello, World!" in
      let open Void in
      let args =
        let l = Array.length Sys.argv in
        if l <= 1 then
          [
            "/bin/ash";
            "-c";
            "/bin/echo hello > /hello.txt && /bin/cat /hello.txt";
          ]
        else Array.sub Sys.argv 1 (l - 1) |> Array.to_list
      in
      let void =
        empty |> rootfs ~mode:RW alpine_img
        |> mount (make_mount ~mode:R ~src:mount_src ~tgt:"data")
        |> exec args
      in
      let t = Void.spawn ~process_mgr:env#process_mgr ~sw void in
      let status = Promise.await (Void.exit_status t) in
      Eio.traceln "Status: %a" Void.pp_exit_status status
