module Make (R : Reagents.S) = struct
  module Countdown_latch = Countdown_latch.Make(R)
  module Exchanger = Exchanger.Make(R)
end