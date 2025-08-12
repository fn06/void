(** {1 Void}

    Void is a library to provide {e void processes}. A void process is an
    {e empty} process, one in which most global resources have been removed. As
    a user, you can add back in precisely those pieces you need for your
    process.

    Void uses Eio's [fork_action]s to provide this mechanism, thus it is only
    available with Eio. *)

module Mount : sig
  module Flags : sig
    type t = private int

    val ms_remount : t
    val ms_bind : t
    val ms_shared : t
    val ( + ) : t -> t -> t
  end

  module Types : sig
    type t = private string

    val btrfs : t
    val ext4 : t
    val auto : t
  end
end

type t
(** A void process *)

type path = string
(** File paths *)

type mode = R | RW
(* Mounting modes *)

type void
(** A configuration for a void process *)

val empty : void
(** The empty void *)

val rootfs : mode:mode -> path -> void -> void
(** Add a new root filesystem *)

val mount : mode:mode -> src:path -> tgt:path -> void -> void
(** Mount a path into the void process *)

val network : string -> void -> void
(** Add a network device *)

val exec : string list -> void -> void
(** Make a void configuration ready to be spawned *)

val fexec : _ Eio.File.ro -> string list -> void -> void
(** Make a void configuration ready to be spawned *)

val spawn : sw:Eio.Switch.t -> void -> t
(** Spawn a void process *)

val pid : t -> int
(** The pid of a running void process *)

val run : void -> Unix.process_status
(** A combination of {! spawn} and awaiting the promise returned by
    {! exit_status} *)

(** {2 Exit status}

    By default, void processes return a {! Unix.process_status} but you can
    convert this to an {! Eio} version.*)

val exit_status : t -> Unix.process_status Eio.Promise.t
(** Obtain a promise for whenever the void process exits *)

val pp_exit_status : Unix.process_status Fmt.t
(** Useful for debugging, a simple pretty-printer for exit statuses *)

val to_eio_status : Unix.process_status -> Eio.Process.exit_status
