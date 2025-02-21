open Eio.Std

let () =
  Eio_linux.run @@ fun _env ->
  Switch.run @@ fun sw ->
  let open Void in
  let void = empty |> exec [] in
  Eio.traceln "Spawning the empty void...";
  let t = Void.spawn ~sw void in
  let status = Promise.await (Void.exit_status t) in
  Eio.traceln "Status: %s" (Void.exit_status_to_string status)
