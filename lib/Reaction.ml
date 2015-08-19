module type S = sig
  type t
  type 'a offer
  val empty : t
  val with_CAS : t -> PostCommitCAS.t -> t
  val with_offer : t -> 'a offer -> t
  val try_commit : t -> bool
  val cas_count  : t -> int
  val has_offer  : t -> 'a offer -> bool
  val union : t -> t -> t
  val with_post_commit : t -> (unit -> unit) -> t
  (* val can_cas_immediate : t -> ('a,'b) Reagent.t -> 'b Offer.t -> bool *)
end

module Make (Sched: Scheduler.S) : S with type 'a offer = 'a Offer.Make(Sched).t = struct
  module Offer = Offer.Make(Sched)

  type 'a offer = 'a Offer.t

  module IntSet = Set.Make (struct
    type t = int
    let compare = compare
  end)

  type t =
    { cases  : PostCommitCAS.t list;
      offers : IntSet.t;
      post_commits : (unit -> unit) list }

  let empty = {cases = []; offers = IntSet.empty; post_commits = []}

  let has_offer {offers; _} offer = IntSet.mem (Offer.get_id offer) offers

  let with_CAS r cas = { r with cases = cas::r.cases }

  let with_post_commit r pc = { r with post_commits = pc::r.post_commits }

  let with_offer r offer =
    { r with offers = IntSet.add (Offer.get_id offer) r.offers }

  let cas_count r = List.length r.cases

  let union r1 r2 =
    { cases = r1.cases @ r2.cases;
      offers = IntSet.union r1.offers r2.offers;
      post_commits = r1.post_commits @ r2.post_commits }

  let try_commit r =
    let success = match r.cases with
      | [] -> Some (fun () -> ())
      | [cas] -> PostCommitCAS.commit cas
      | l -> PostCommitCAS.kCAS l
    in
    match success with
    | None -> false
    | Some pc ->
      ( pc ();
        List.iter (fun f -> f ()) r.post_commits;
        true)

end