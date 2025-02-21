open Eio.Std

let ( / ) = Eio.Path.( / )

let copy_hey fs =
  let temp_dir = Filename.temp_dir "void-" "-world" in
  let hey = Eio.Path.load (fs / "./examples/hey") in
  Eio.Path.save ~create:(`If_missing 0o755) (fs / temp_dir / "hey") hey;
  temp_dir

(* This mounts the hello-world into the void process. *)
let () =
  Eio_posix.run @@ fun env ->
  Switch.run @@ fun sw ->
  let hey_dir = copy_hey env#fs in
  let void =
    let open Void in
    empty |> mount ~mode:R ~src:hey_dir ~tgt:"say" |> exec [ "/say/hey" ]
  in
  let t = Void.spawn ~sw void in
  let status = Promise.await (Void.exit_status t) in
  Eio.traceln "Void process: %s" (Void.exit_status_to_string status)
