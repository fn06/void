let copy_hey fs =
  let temp_dir = Filename.temp_dir "void-" "-world" in
  let hey = Eio.Path.(load (fs / "./examples/hey")) in
  Eio.Path.(save ~create:(`If_missing 0o755) (fs / temp_dir / "hey")) hey;
  temp_dir

(* This mounts the hello-world into the void process. *)
let () =
  Eio_posix.run @@ fun env ->
  let hey_dir = copy_hey env#fs in
  let void =
    let open Void in
    empty |> mount ~mode:R ~src:hey_dir ~tgt:"say" |> exec [ "/say/hey" ]
  in
  let status = Void.run void in
  Eio.traceln "Void process: %a" Void.pp_exit_status status
