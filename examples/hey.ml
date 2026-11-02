let () =
  Eio_posix.run @@ fun env ->
  Eio.Path.(with_open_in (env#cwd / "./examples/hey")) @@ fun file ->
  let void = Void.empty |> Void.fexec file [] in
  Eio.Switch.run @@ fun sw ->
  let status =
    Void.spawn_hermetic ~sw void |> Void.exit_status |> Eio.Promise.await
  in
  Eio.traceln "Void process: %a" Void.pp_exit_status status
