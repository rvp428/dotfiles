# Dotfiles Maintainability Plan

This repository contains the implementation plan produced from the maintainability review on 2026-07-13.

- [Detailed plan](maintainability-plan.md): phased changes, design choices, validation, and rollout order.

## Scope

The plan improves maintainability and removes duplicated configuration without changing the intended workstation behavior. It deliberately does not include unrelated changes already present in the working tree, including the SSH-host enhancements in `home-manager/common.nix`.

## Recommended sequence

1. Establish the devshell contract and consolidate Poetry shells.
2. Extract common wrapper behavior from Just recipes.
3. Make Home Manager feature modules discoverable and composable.
4. Remove remaining shell/AWS/package duplication.

Each phase is independently reviewable and should leave the repository passing its applicable checks before the next phase starts.
