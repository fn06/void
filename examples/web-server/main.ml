let ( / ) = Eio.Path.( / )

let which proc exec =
  Eio.Process.parse_out proc Eio.Buf_read.take_all [ "which"; exec ]
  |> String.trim

let caddy proc =
  Void.empty |> Void.tmp_rootfs ~mode:RW
  |> Void.mount (Void.make_mount ~mode:R ~src:"/nix" ~tgt:"/nix")
  |> Void.mount (Void.make_mount ~mode:R ~src:"/var/www" ~tgt:"/www")
  |> Void.exec [ which proc "caddy" ]

let () =
  Eio_posix.run @@ fun env ->
  assert (Eio.Path.is_directory (env#fs / "/nix/store"));
  let caddy = caddy env#process_mgr in
  Fmt.pr "%a\n%!" Void.pp_exit_status @@ Void.run caddy
