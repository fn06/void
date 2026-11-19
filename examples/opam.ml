open Eio.Std

let ( / ) = Eio.Path.( / )

let () =
  Eio_posix.run @@ fun env ->
  Switch.run @@ fun sw ->
  let fs = env#fs in
  let proc = env#process_mgr in
  let alpine_img = Image.get_image ~fs ~proc "ocaml/opam:alpine" in
  let open Void in
  let args = [ "/bin/sh"; "-c"; "whoami" ] in
  let uids, gids =
    Void.default_maps ~subuid:(env#fs / "/etc/subuid")
      ~subgid:(env#fs / "/etc/subgid")
  in
  let void =
    empty |> rootfs ~mode:R alpine_img
    |> fork_actions [ Eio_unix.Private.Fork_action.setuid 1000 ]
    |> uid_map uids |> gid_map gids |> exec args
  in
  let t = Void.spawn ~process_mgr:env#process_mgr ~sw void in
  let status = Promise.await (Void.exit_status t) in
  Eio.traceln "Status: %a" Void.pp_exit_status status
