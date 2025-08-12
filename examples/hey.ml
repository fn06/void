let () =
  Eio_posix.run @@ fun env ->
  Eio.Path.(with_open_in (env#cwd / "./examples/hey")) @@ fun file ->
  let void =
    let open Void in
    empty |> fexec file []
  in
  let status = Void.run void in
  Eio.traceln "Void process: %a" Void.pp_exit_status status
