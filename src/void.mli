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

type _ config
(** A configuration for a void process *)

type yes = Yes
type no = No

val empty : < rootfs : yes ; network : no ; exec : no > config
(** The empty void *)

val rootfs :
  mode:mode ->
  path ->
  < rootfs : _ ; network : 'n ; exec : 'e > config ->
  < rootfs : yes ; network : 'n ; exec : 'e > config
(** Add a new root filesystem *)

val tmp_rootfs :
  mode:mode ->
  < rootfs : _ ; network : 'n ; exec : 'e > config ->
  < rootfs : yes ; network : 'n ; exec : 'e > config
(** Request a tmpdir rootfs (this is the default with [mode = R]). *)

val mount : mode:mode -> src:path -> tgt:path -> 'a config -> 'a config
(** Mount a path into the void process *)

val network :
  string ->
  < rootfs : 'r ; network : no ; exec : 'e > config ->
  < rootfs : 'r ; network : yes ; exec : 'e > config
(** Add a network device *)

val exec : string list -> 'a config -> 'a config
(** Make a void configuration ready to be spawned *)

val fexec : _ Eio.File.ro -> string list -> 'a config -> 'a config
(** Make a void configuration ready to be spawned *)

val spawn : sw:Eio.Switch.t -> _ config -> t
(** Spawn a void process *)

val spawn_hermetic :
  sw:Eio.Switch.t -> < rootfs : _ ; network : no ; exec : _ > config -> t
(** Like {!spawn} except, it requires the configuration to have no network
    access. *)

val pid : t -> int
(** The pid of a running void process *)

val run : 'a config -> Unix.process_status
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
