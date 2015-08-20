module type S = sig
  type ('a,'b) t
  val never    : ('a,'b) t
  val constant : 'a -> ('b,'a) t
  val (>>)     : ('a,'b) t -> ('b,'c) t -> ('a,'c) t
end