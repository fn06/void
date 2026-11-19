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

type mount
(** The type for mounts. *)

type yes = Yes
type no = No

val empty : < rootfs : yes ; network : no ; exec : no > config
(** The empty void *)

(** {2 Mount namespace}

    All void processes are initially created in a new mount namespace, and
    without any user configuration, the processes will be run in a new, empty
    directory mounted on [/].

    Use {! rootfs} to set up the pivot root. You can also specifically request a
    temporary directory too using {! tmp_rootfs}.

    Additional mounts can be specified with {! mount}. *)

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

val make_mount : src:path -> tgt:path -> mode:mode -> mount
(** [make_mount ~src ~tgt ~mode] *)

val mount : mount -> 'a config -> 'a config
(** Mount a path into the void process *)

(** {2 Network Namespaces}

    All void processes are initially created without any network device except a
    loopback.

    You can use {! network} to specify the name of the network device you wish
    to be included in the namespace. *)

val network :
  string ->
  < rootfs : 'r ; network : no ; exec : 'e > config ->
  < rootfs : 'r ; network : yes ; exec : 'e > config
(** Add a network device *)

(** {2 User namespaces}

    All void processes are created initially in a new user namespace without any
    UID (or GID) mapping. This results in a process with a namespace UID of
    nobody.

    You can set the UID and GID mapping manually with {! uid_map} and
    {! gid_map}. Note that these functions do not check for the validity of the
    maps you provide.

    Alternatively, you can use {! default_maps} which will map the namespace
    root to the host user who is creating the namespace, and then use the values
    in [/etc/subuid] to map the rest of the namespace (similarly for GID). *)

type uns_map = (int * int * int) list
(** A user namespace map. *)

val uid_map : uns_map -> 'a config -> 'a config
(** Provide a UID map that will be passed to [newuidmap]. *)

val gid_map : uns_map -> 'a config -> 'a config
(** Provide a UID map that will be passed to [newgidmap]. *)

val default_maps :
  subuid:_ Eio.Path.t -> subgid:_ Eio.Path.t -> uns_map * uns_map
(** Creates default maps using the supplied paths to [/etc/subuid] and
    [/etc/subgid], alongside mapping the root to the calling user.

    To be safe, this function fails if the calling user is root. *)

val fork_actions : Eio_unix.Private.Fork_action.t list -> 'a config -> 'a config
(** An escape hatch to add more fork actions. *)

val exec : string list -> 'a config -> 'a config
(** Make a void configuration ready to be spawned. *)

val fexec : _ Eio.File.ro -> string list -> 'a config -> 'a config
(** Like {! exec} except a file descriptor is passed instead of a path to the
    executable. *)

val spawn : process_mgr:_ Eio.Process.mgr -> sw:Eio.Switch.t -> _ config -> t
(** Spawn a void process *)

val spawn_hermetic :
  process_mgr:_ Eio.Process.mgr ->
  sw:Eio.Switch.t ->
  < rootfs : _ ; network : no ; exec : _ > config ->
  t
(** Like {!spawn} except, it requires the configuration to have no network
    access. *)

val pid : t -> int
(** The pid of a running void process *)

val run : process_mgr:_ Eio.Process.mgr -> 'a config -> Unix.process_status
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
(** Convert a {! Unix.process_status} into an Eio status. *)

(** {2 Private}

    The {! Private} module provides access to the low-level fork actions amongst
    other expert tools. Most users should not need to interact with these. *)
module Private : sig
  module Fork_actions : sig
    val pivot_root :
      ?mounts:mount list ->
      root:string ->
      mode ->
      Eio_unix.Private.Fork_action.t
    (** The pivot root fork action. *)

    val configure_user_namespace :
      process_mgr:_ Eio.Process.mgr -> pid:int -> uns_map -> uns_map -> unit
    (** Uses [newuidmap] and [newgidmap] to confgiure the namespaces based on
        the {! uns_map}s that are supplied. *)
  end

  val fork_actions :
    Eio_unix.Private.Fork_action.t list -> int * Unix.file_descr
  (** [fork_actions actions] will fork a new process and return the
      [(pid, pid_fd)] of the parent and the child. Unlike most of the APIs, this
      allows you to run actions and then carry on with OCaml code. *)
end
