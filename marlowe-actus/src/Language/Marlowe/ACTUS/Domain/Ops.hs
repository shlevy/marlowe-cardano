{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Language.Marlowe.ACTUS.Domain.Ops where

import Data.Time (LocalTime)
import Language.Marlowe
import Language.Marlowe.ACTUS.Domain.ContractTerms (CR (..), DCC (..))
import Language.Marlowe.ACTUS.Utility.YearFraction (yearFraction)

marloweFixedPoint :: Integer
marloweFixedPoint = 1000000

class ActusOps a where
    _min  :: a -> a -> a
    _max  :: a -> a -> a
    _abs  :: a -> a
    _zero :: a
    _one  :: a
    _fromInteger :: Integer -> a
    _negate :: a -> a

class Eq a => ActusNum a where
    (+) :: a -> a -> a
    (-) :: a -> a -> a
    (*) :: a -> a -> a
    (/) :: a -> a -> a

class YearFractionOps b where
    _y :: DCC -> LocalTime -> LocalTime -> Maybe LocalTime -> b

class ScheduleOps b where
    _ceiling :: b -> Integer

class (ActusNum a, ActusOps a) => RoleSignOps a where
    _r :: CR -> a
    _r CR_RPA = _one
    _r CR_RPL = _negate _one
    _r CR_CLO = _one
    _r CR_CNO = _one
    _r CR_COL = _one
    _r CR_LG  = _one
    _r CR_ST  = _negate _one
    _r CR_BUY = _one
    _r CR_SEL = _negate _one
    _r CR_RFL = _one
    _r CR_PFL = _negate _one
    _r CR_RF  = _one
    _r CR_PF  = _negate _one

instance RoleSignOps Double
instance RoleSignOps (Value Observation)

instance ActusOps Double where
    _min  = min
    _max  = max
    _abs  = abs
    _zero = 0.0
    _one  = 1.0
    _fromInteger = fromInteger
    _negate = negate

instance ActusNum Double where
    a + b       = a Prelude.+ b
    a - b       = a Prelude.- b
    a * b       = a Prelude.* b
    a / b       = a Prelude./ b

instance YearFractionOps Double where
    _y = yearFraction

instance ScheduleOps Double where
    _ceiling = ceiling

instance YearFractionOps (Value Observation) where
    _y a b c d = Constant . toMarloweFixedPoint $ yearFraction a b c d
      where
        toMarloweFixedPoint = round <$> (fromIntegral marloweFixedPoint Prelude.*)

instance ScheduleOps (Value Observation) where
    _ceiling (Constant a) = ceiling $ (fromInteger  a :: Double) Prelude./ (fromInteger marloweFixedPoint :: Double)
    -- ACTUS is implemented only for Fixed Schedules
    -- that means schedules are known before the contract
    -- is exectued, resp. the schedule do not depend on
    -- riskfactors
    _ceiling _            = error "Precondition: Fixed schedules"

instance ActusOps (Value Observation) where
    _min a b = Cond (ValueLT a b) a b
    _max a b = Cond (ValueGT a b) a b
    _abs a = _max a (SubValue _zero a)
    _zero = Constant 0
    _one  = Constant marloweFixedPoint
    _fromInteger n = Constant $ n Prelude.* marloweFixedPoint
    _negate a = NegValue a

infixl 7  *, /
infixl 6  +, -

-- In order to have manageble contract sizes, we need to reduce Value as
-- good as possible. Note: this interfers with the semantics - ideally
-- we would have formally verified reduction semantics instead
instance ActusNum (Value Observation) where
  x + y = reduceValue $ AddValue x y
  x - y = reduceValue $ SubValue x y
  x * y = reduceValue $ DivValue (MulValue x y) (Constant marloweFixedPoint)
  x / y = reduceValue $ MulValue (DivValue x y) (Constant marloweFixedPoint)

reduceContract :: Contract -> Contract
reduceContract Close = Close
reduceContract (Pay a b c d e) = Pay a b c (reduceValue d) (reduceContract e)
reduceContract (When cs t c) = When (map f cs) t (reduceContract c)
  where
    f (Case a x)           = Case a (reduceContract x)
    f (MerkleizedCase a x) = MerkleizedCase a x
reduceContract (If obs a b) = let c = evalObservation env state obs in if c then reduceContract a else reduceContract b
  where
    env = Environment {timeInterval = (POSIXTime 0, POSIXTime 0)}
    state = emptyState $ POSIXTime 0
reduceContract (Let v o c) = Let v (reduceValue o) (reduceContract c)
reduceContract (Assert o c) = Assert (reduceObservation o) (reduceContract c)

reduceObservation :: Observation -> Observation
reduceObservation (AndObs a b)  = AndObs (reduceObservation a) (reduceObservation b)
reduceObservation (OrObs a b)   = OrObs (reduceObservation a) (reduceObservation b)
reduceObservation (NotObs a)    = NotObs (reduceObservation a)
reduceObservation (ValueGE a b) = ValueGE (reduceValue a) (reduceValue b)
reduceObservation (ValueGT a b) = ValueGT (reduceValue a) (reduceValue b)
reduceObservation (ValueLE a b) = ValueLE (reduceValue a) (reduceValue b)
reduceObservation (ValueLT a b) = ValueLT (reduceValue a) (reduceValue b)
reduceObservation (ValueEQ a b) = ValueEQ (reduceValue a) (reduceValue b)
reduceObservation x             = x

reduceValue :: Value Observation -> Value Observation
reduceValue = converge reduceValue'
  where
    converge :: Eq a => (a -> a) -> a -> a
    converge = until =<< ((==) =<<)

    reduceValue' :: Value Observation -> Value Observation
    reduceValue' (ChoiceValue i) = ChoiceValue i
    reduceValue' (UseValue i) = UseValue i
    reduceValue' (Constant i) = Constant i
    reduceValue' (AddValue (Constant x) (Constant y)) = Constant $ x Prelude.+ y
    reduceValue' (AddValue (Constant 0) x) = x
    reduceValue' (AddValue x (Constant 0)) = x
    reduceValue' (AddValue x y) = AddValue (reduceValue' x) (reduceValue' y)
    reduceValue' (SubValue (Constant x) (Constant y)) = Constant $ x Prelude.- y
    reduceValue' (SubValue x (Constant 0)) = x
    reduceValue' (SubValue (Constant 0) x) = NegValue x
    reduceValue' (SubValue x y) = SubValue (reduceValue' x) (reduceValue' y)
    reduceValue' (MulValue (Constant x) (Constant y)) = Constant $ x Prelude.* y
    -- imp
    reduceValue' (MulValue (DivValue a b) (DivValue x y)) = DivValue (MulValue (reduceValue' a) (reduceValue' x)) (MulValue (reduceValue' b) (reduceValue' y))
    reduceValue' (MulValue (DivValue a b) (Constant x)) = DivValue (MulValue (reduceValue' a) (Constant x)) (reduceValue' b)
    reduceValue' (MulValue x y) = MulValue (reduceValue' x) (reduceValue' y)
    reduceValue' (DivValue (Constant x) (Constant y)) | rem x y == 0 = Constant (x `div` y)
    -- same as in Semantics
    reduceValue' (DivValue (Constant n) (Constant d)) =
      Constant $
        if n == 0 || d == 0
          then 0
          else
            let (q, r) = n `quotRem` d
                ar = abs r Prelude.* 2
                ad = abs d
             in if ar < ad
                  then q -- reminder < 1/2
                  else
                    if ar > ad
                      then q Prelude.+ signum n Prelude.* signum d -- reminder > 1/2
                      else
                        let -- reminder == 1/2
                            qIsEven = q `div` 2 == 0
                         in if qIsEven then q else q Prelude.+ signum n Prelude.* signum d
    reduceValue' (DivValue x y) = DivValue (reduceValue' x) (reduceValue' y)
    reduceValue' (NegValue (Constant x)) = Constant $ - x
    reduceValue' (NegValue v) = NegValue (reduceValue' v)
    reduceValue' (Cond (ValueGT (Constant x) (Constant y)) a _) | x > y = reduceValue' a
    reduceValue' (Cond (ValueGT (Constant _) (Constant _)) _ b) = reduceValue' b
    reduceValue' (Cond (ValueLT (Constant x) (Constant y)) a _) | x < y = reduceValue' a
    reduceValue' (Cond (ValueLT (Constant _) (Constant _)) _ b) = reduceValue' b
    reduceValue' (Cond o a b) = Cond (reduceObservation o) (reduceValue' a) (reduceValue' b)
    reduceValue' x = x
