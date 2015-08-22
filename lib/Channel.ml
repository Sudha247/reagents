module type S = sig
  type ('a,'b) endpoint
  type ('a,'b) reagent

  val mk_chan : unit -> ('a,'b) endpoint * ('b,'a) endpoint
  val swap    : ('a,'b) endpoint -> ('a,'b) reagent
end

module Make (Sched : Scheduler.S) : S with
  type ('a,'b) reagent = ('a,'b) Reagent.Make(Sched).t = struct

  module Reagent = Reagent.Make(Sched)
  module Reaction = Reaction.Make(Sched)
  module Offer = Offer.Make(Sched)

  open Reagent

  type ('a,'b) reagent = ('a,'b) Reagent.t

  type ('a,'b) message =
    Message : 'a * Reaction.t * ('b, 'c) t * 'c Offer.t -> ('a,'b) message

  let can_cas_immediate k rx = function
    | Some _ -> false
    | None -> Reaction.cas_count rx = 0 && k.always_commits

  type ('a,'b) endpoint =
    { outgoing: ('a,'b) message MSQueue.t;
      incoming: ('b,'a) message MSQueue.t }

  let mk_chan () =
    let l1 = MSQueue.create () in
    let l2 = MSQueue.create () in
    {incoming = l1; outgoing = l2},
    {incoming = l2; outgoing = l1}

  let rec swap : 'a 'b 'r. ('a,'b) endpoint -> ('b,'r) reagent -> ('a,'r) reagent =
    fun ep k ->
      let {outgoing; incoming} = ep in
      let try_react a rx offer =
        (* Merged continuation *)
        let swapK payload sender_rx sender_offer =
          let swapk_try_react c receiver_rx receiver_offer =
            let rx = Reaction.union sender_rx receiver_rx in
            let cas = Offer.complete sender_offer c in
            let new_rx =
              if can_cas_immediate k receiver_rx receiver_offer then
                match PostCommitCAS.commit cas with
                | None -> None
                | Some f -> ( f (); Some rx )
              else Some (Reaction.with_CAS rx cas)
            in
            match new_rx with
            | None -> Retry
            | Some new_rx -> k.try_react payload new_rx receiver_offer
          in
          { always_commits = false;
            may_sync = k.may_sync;
            compose = (fun _ -> failwith "swapK.compose : impossible");
            try_react = swapk_try_react }
        in
        (* Search for matching offers *)
        let rec try_from cursor retry =
          match MSQueue.next cursor with
          | None -> if (retry) then Retry else Block
          | Some (Message (payload,sender_rx,sender_k,sender_offer), cursor) ->
              let same_offer o = function
              | None -> false
              | Some o' -> Offer.equal o o'
              in
              ( if (not (Offer.is_active sender_offer))
                  || Reaction.has_offer rx sender_offer
                  || same_offer sender_offer offer then
                    try_from cursor retry
                else (* Found matching offer *)
                  let new_rx = Reaction.with_offer rx sender_offer in
                  let merged = sender_k.compose (swapK payload sender_rx sender_offer) in
                  match merged.try_react a new_rx offer with
                  | Retry -> try_from cursor true
                  | Block -> try_from cursor retry
                  | v -> v )
        in
        let () = match offer with
          | None -> ()
          | Some offer -> (* XXX KC: if !k.may_sync then *)
              MSQueue.push outgoing (Message (a,rx,k,offer))
        in
        try_from (MSQueue.snapshot incoming) false
      in
      { always_commits = false;
        may_sync = true;
        compose = (fun next -> swap ep (k.compose next));
        try_react }

  let swap ep = swap ep Reagent.commit
end
