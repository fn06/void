open Eio.Std

(* This example read-only mounts a copy of busybox
   into the root-filesystem of the process. *)
let () =
  Eio_posix.run @@ fun env ->
  Switch.run @@ fun sw ->
  let fs = env#fs in
  let proc = env#process_mgr in
  let alpine_img = Image.get_image ~fs ~proc "alpine/curl" in
  let open Void in
  let args =
    let l = Array.length Sys.argv in
    if l <= 1 then [ "/bin/ls"; "-l" ]
    else Array.sub Sys.argv 1 (l - 1) |> Array.to_list
  in
  let void = empty |> rootfs ~mode:R alpine_img |> exec args in
  let t = Void.spawn ~process_mgr:env#process_mgr ~sw void in
  let status = Promise.await (Void.exit_status t) in
  Eio.traceln "Status: %a" Void.pp_exit_status status
