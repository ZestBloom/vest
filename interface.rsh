"reach 0.1";
"use strict";
// -----------------------------------------------
// Name: KINN Base (starter)
// Version: 0.1.0 - starter initial
// Requires Reach v0.1.11-rc7 (27cb9643) or later
// ----------------------------------------------

import {
  State as BaseState,
  Params as BaseParams,
  view,
  baseState,
  baseEvents
} from "@KinnFoundation/base#base-v0.1.11r13:interface.rsh";

// CONSTANTS

const SERIAL_VER = 0;

// TYPES

export const StarterState = Struct([
  /* add your state here */
]);

export const State = Struct([
  ...Struct.fields(BaseState),
  ...Struct.fields(StarterState),
]);

export const StarterParams = Object({
  /* add your params here */
});

export const Params = Object({
  ...Object.fields(BaseParams),
  ...Object.fields(StarterParams),
});

// FUN

const fState = (State) => Fun([], State);

// REMOTE FUN

export const rState = (ctc, State) => {
  const r = remote(ctc, { state: fState(State) });
  return r.state();
};

// CONTRACT

export const Event = () => [Events({ ...baseEvents })];
export const Participants = () => [
  Participant("Manager", {
    getParams: Fun([], Params),
  }),
  Participant("Relay", {}),
];
export const Views = () => [View(view(State))];
export const Api = () => [];
export const App = (map) => {
  const [{ amt, ttl }, [addr, _], [Manager, Relay], [v], _, [e]] = map;
  Manager.publish()
    .pay(amt + SERIAL_VER)
    .timeout(relativeTime(ttl), () => {
      Anybody.publish();
      commit();
      exit();
    });
  transfer(amt + SERIAL_VER).to(addr);
  e.appLaunch();
  const initialState = {
    ...baseState(Manager),
  };
  v.state.set(State.fromObject(initialState));
  commit();
  Relay.publish();
  e.appClose();
  commit();
  Relay.publish();
  commit();
  exit();
};
// ----------------------------------------------
