let replace_slashes = String.map (function '/' | ':' -> '-' | c -> c)

let get_image ~fs ~proc image =
  let tmpdir = Filename.temp_dir "void" (replace_slashes image) in
  Eio.traceln "Extracting %s to %s..." image tmpdir;
  let container_id =
    Eio.Process.parse_out proc Eio.Buf_read.take_all
      [ "docker"; "run"; "-d"; image ]
    |> String.trim
  in
  Eio.traceln "Container %s" container_id;
  let () =
    Eio.Process.run proc
      [
        "docker";
        "export";
        container_id;
        "-o";
        Filename.concat tmpdir "image.tar.gz";
      ]
  in
  Eio.traceln "Untarring...";
  Eio.Path.mkdir ~perm:0o777 Eio.Path.(fs / tmpdir / "rootfs");
  let () =
    Eio.Process.run proc
      [
        "tar";
        "-xf";
        Filename.concat tmpdir "image.tar.gz";
        "-C";
        Filename.concat tmpdir "rootfs";
      ]
  in
  Filename.concat tmpdir "rootfs"
