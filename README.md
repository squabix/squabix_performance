# SQUABIX Performance

Small tools to keep a busy 3D scene fast.

## Classes

- `IntervalStaggerer`
- `CullingController3D`
- `MeshInstanceAggregator3D`
- `VisibilityAnimationPlayer`
- `Prewarmer`

## Use

1. `IntervalStaggerer` calls methods on a timer. Each copy has a small random delay, so they do not all run on the same frame. Fill `target_methods`.
2. `CullingController3D` turns off processing and hides nodes by distance and screen view. Set `root`.
3. `MeshInstanceAggregator3D` joins meshes into `MultiMesh` nodes. Set `mesh_source`, then press Aggregate.
4. `VisibilityAnimationPlayer` is an `AnimationPlayer` made for animating meshes that `MeshInstanceAggregator3D` has batched. It shows nodes when it plays and hides them when it ends.
5. `Prewarmer` draws scenes and materials once, so they do not stutter later. Fill it in, then call `Prewarmer.warm_all()`.

## Demo

See it in the game: https://github.com/squabix/craftlander

## Needs

Godot 4.5 or newer.

## License

MIT. See `LICENSE`.
Icons are from another project. See `THIRD_PARTY.md`.
