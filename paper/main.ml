let ( / ) = Eio.Path.( / )

let completely_empty _cwd =
  Fmt.pr "Void process: %a\n%!" Void.pp_exit_status (Void.run Void.empty)

let static cwd =
  Eio.Path.with_open_in (cwd / "paper/hello") @@ fun file ->
  let void = Void.empty |> Void.fexec file [ "hello from the void!" ] in
  let status = Void.run void in
  Fmt.pr "Void process: %a\n%!" Void.pp_exit_status status

let () =
  Eio_posix.run @@ fun env ->
  let cwd = Eio.Stdenv.cwd env in
  Eio.traceln "Empty.";
  completely_empty cwd;
  Eio.traceln "Static.";
  static cwd
