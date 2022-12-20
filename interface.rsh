"reach 0.1";
"use strict";
// -----------------------------------------------
// Name: KINN Vest
// Version: 0.1.0 - vest initial
// Requires Reach v0.1.11-rc7 (27cb9643) or later
// ----------------------------------------------

import {
  State as BaseState,
  Params as BaseParams,
  TokenState,
  view,
  baseState,
  baseEvents,
  Triple,
  fState,
  max,
  min
} from "@KinnFoundation/base#base-v0.1.11r15:interface.rsh";

// CONSTANTS

const SERIAL_VER = 0;

// TYPES

export const VestingState = Struct([
  ["tokenSupply", UInt],
  ["who", Address],
  ["withdraws", UInt],
  ["terrain", Triple(UInt)],
  ["frozen", Bool],
  ["lastConcensusTime", UInt],
  ["vestUnit", UInt],
  ["vestPeriod", UInt],
  ["managerEnabled", Bool],
  ["recipientEnabled", Bool],
  ["delegateEnabled", Bool],
  ["anybodyEnabled", Bool],
]);

export const State = Struct([
  ...Struct.fields(BaseState),
  ...Struct.fields(TokenState),
  ...Struct.fields(VestingState),
]);

export const VestingParams = Object({
  tokenAmount: UInt, // amount of tokens to vest
  recipientAddr: Address, // address of the recipient
  delegateAddr: Address, // address of the delegate
  cliffTime: UInt, // cliff network seconds
  vestTime: UInt, // vesting network seconds
  vestPeriod: UInt, // vesting minimum period
  vestMultiplierD: UInt, // vesting multiplier (delegate)
  vestMultiplierA: UInt, // vesting multiplier (anybody)
  defaultFrozen: Bool, // default frozen
  managerEnabled: Bool, // manager enabled
  recipientEnabled: Bool, // recipient enabled
  delegateEnabled: Bool, // delegate enabled
  anybodyEnabled: Bool, // anybody enabled
});

export const Params = Object({
  ...Object.fields(BaseParams),
  ...Object.fields(VestingParams),
});

// FUN

const fTouch = Fun([], Null);
const fToggle = Fun([], Null);
const fCancel = Fun([], Null);
const fWithdraw = Fun([], Null);
const fDelegateWidthdraw = Fun([], Null);
const fAnybodyWithdraw = Fun([], Null);

// REMOTE FUN

export const rState = (ctc, State) => {
  const r = remote(ctc, { state: fState(State) });
  return r.state();
};

// API

const api = {
  touch: fTouch,
  toggle: fToggle,
  cancel: fCancel,
  withdraw: fWithdraw,
  delegateWithdraw: fDelegateWidthdraw,
  anybodyWithdraw: fAnybodyWithdraw,
};

// CONTRACT

export const Event = () => [Events({ ...baseEvents })];
export const Participants = () => [
  Participant("Manager", {
    getParams: Fun([], Params),
  }),
  Participant("Relay", {}),
  Participant("Eve", {}),
];
export const Views = () => [View(view(State))];
export const Api = () => [API(api)];
export const App = (map) => {
  const [
    { amt, ttl, tok0: token },
    [addr, _],
    [Manager, Relay, _],
    [v],
    [a],
    [e],
  ] = map;
  Manager.only(() => {
    const {
      tokenAmount,
      recipientAddr,
      delegateAddr,
      cliffTime,
      vestTime,
      vestPeriod,
      vestMultiplierD,
      vestMultiplierA,
      defaultFrozen,
      managerEnabled,
      recipientEnabled,
      delegateEnabled,
      anybodyEnabled,
    } = declassify(interact.getParams());
  });
  Manager.publish(
    tokenAmount,
    recipientAddr,
    delegateAddr,
    cliffTime,
    vestTime,
    vestPeriod,
    vestMultiplierD,
    vestMultiplierA,
    defaultFrozen,
    managerEnabled,
    recipientEnabled,
    delegateEnabled,
    anybodyEnabled
  )
    .check(() => {
      check(tokenAmount > 0, "tokenAmount must be greater than 0");
      check(cliffTime > 0, "cliffTime must be greater than 0");
      check(vestTime > 0, "vestTime must be greater than 0");
      check(
        vestMultiplierD >= 2,
        "vestMultiplierD must be greater than or equal to 2"
      );
      check(
        vestMultiplierA >= 2 * vestMultiplierD,
        "vestMultiplierA must be greater than or equal to 2 * vestMultiplierD"
      );
    })
    .pay([amt + SERIAL_VER, [tokenAmount, token]])
    .timeout(relativeTime(ttl), () => {
      Anybody.publish();
      commit();
      exit();
    });
  transfer(amt + SERIAL_VER).to(addr);
  e.appLaunch();

  // ---------------------------------------------
  // Vesting Contract Main Step
  // ---------------------------------------------

  const isBurn = !recipientEnabled && !delegateEnabled && !anybodyEnabled;

  const terrain = [
    cliffTime,
    cliffTime + vestTime * vestMultiplierD,
    cliffTime + vestTime * vestMultiplierA,
  ];

  const vestUnit = tokenAmount / vestTime;

  const TERRAIN_CLIFF0 = 0;
  const TERRAIN_CLIFF1 = 1;
  const TERRAIN_CLIFF2 = 2;

  const initialState = {
    ...baseState(Manager),
    token,
    tokenAmount,
    tokenSupply: tokenAmount,
    who: recipientAddr,
    withdraws: 0,
    terrain,
    frozen: defaultFrozen,
    lastConcensusTime: thisConsensusTime(),
    vestUnit,
    vestPeriod,
    managerEnabled,
    recipientEnabled,
    delegateEnabled,
    anybodyEnabled,
  };

  const [s] = parallelReduce([initialState])
    .define(() => {
      v.state.set(State.fromObject(s));
    })
    .invariant(
      implies(!s.closed, balance(token) == s.tokenAmount),
      "token balance accurate before closed"
    )
    .invariant(
      implies(s.closed, balance(token) == 0),
      "token balance accurate after closed"
    )
    .invariant(
      implies(!s.closed, balance() == 0),
      "balance accurate before closed"
    )
    .invariant(
      implies(s.closed, balance() == 0),
      "balance accurate after closed"
    )
    .while(!s.closed)
    // api: touch
    // anyone can touch
    .api_(a.touch, () => {
      return [
        (k) => {
          k(null);
          return [s];
        },
      ];
    })
    // api: toggle
    // only manager can toggle if enabled and not burn
    .api_(a.toggle, () => {
      check(managerEnabled, "manager cannot toggle");
      check(!isBurn, "burn contract cannot toggle");
      check(this == Manager, "only manager can toggle");
      return [
        (k) => {
          k(null);
          return [
            {
              ...s,
              frozen: !s.frozen,
            },
          ];
        },
      ];
    })
    // api: cancel
    // only manager can cancel if enabled and not burn
    .api_(a.cancel, () => {
      check(managerEnabled, "manager cannot cancel");
      check(!isBurn, "burn contract cannot cancel");
      check(this == Manager, "only manager can cancel");
      return [
        (k) => {
          k(null);
          transfer([[s.tokenAmount, token]]).to(this);
          return [{ ...s, closed: true, tokenAmount: 0 }];
        },
      ];
    })
    // api: withdraw
    // anyone can withdraw to recipient
    .define(() => {
      const calculateVestAmount = (CTime) => {
        const rTime = max(s.lastConcensusTime, terrain[TERRAIN_CLIFF0]);
        if (CTime > rTime) {
          const dTime =
            CTime - max(s.lastConcensusTime, terrain[TERRAIN_CLIFF0]);
          if (dTime > vestPeriod) {
            return min(dTime * vestUnit, s.tokenAmount);
          } else {
            return 0;
          }
        } else {
          return 0;
        }
      };
    })
    .api_(a.withdraw, () => {
      check(recipientEnabled, "recipientEnabled is false");
      check(!s.frozen, "contract is frozen");
      return [
        (k) => {
          k(null);
          const time = thisConsensusTime();
          const vestAmount = calculateVestAmount(time);
          require(time >= terrain[TERRAIN_CLIFF0], "cliffTime0 not reached");
          require(s.tokenAmount >= vestAmount, "insufficient token amount");
          if (vestAmount > 0) {
            transfer([[vestAmount, token]]).to(recipientAddr);
            return [
              {
                ...s,
                tokenAmount: s.tokenAmount - vestAmount,
                withdraws: s.withdraws + 1,
                lastConcensusTime: time,
                closed: s.tokenAmount - vestAmount == 0,
              },
            ];
          } else {
            return [s];
          }
        },
      ];
    })
    // api: delegateWithdraw
    // only delegate can withdraw to self
    .api_(a.delegateWithdraw, () => {
      check(delegateEnabled, "delegateEnabled is false");
      check(this == delegateAddr, "only delegate can withdraw");
      check(!s.frozen, "contract is frozen");
      check(lastConsensusTime() >= terrain[TERRAIN_CLIFF1], "cliffTime1 not reached")
      return [
        (k) => {
          k(null);
          require(thisConsensusTime() >=
            terrain[TERRAIN_CLIFF1], "cliffTime1 not reached");
          transfer([[s.tokenAmount, token]]).to(this);
          return [
            {
              ...s,
              tokenAmount: 0,
              withdraws: s.withdraws + 1,
              lastConcensusTime: thisConsensusTime(),
              closed: true,
            },
          ];
        },
      ];
    })
    // api: anybodyWithdraw
    // anybody can withdraw to self
    .api_(a.anybodyWithdraw, () => {
      check(anybodyEnabled, "anybodyEnabled is false");
      check(!s.frozen, "contract is frozen");
      check(lastConsensusTime() >= terrain[TERRAIN_CLIFF2], "cliffTime2 not reached")
      return [
        (k) => {
          k(null);
          require(thisConsensusTime() >=
            terrain[TERRAIN_CLIFF2], "cliffTime2 not reached");
          transfer([[s.tokenAmount, token]]).to(this);
          return [
            {
              ...s,
              tokenAmount: 0,
              withdraws: s.withdraws + 1,
              lastConcensusTime: thisConsensusTime(),
              closed: true,
            },
          ];
        },
      ];
    })
    .timeout(false);
  e.appClose();
  commit();
  Relay.publish();
  commit();
  exit();
};
// ----------------------------------------------
