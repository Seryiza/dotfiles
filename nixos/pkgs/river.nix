{ river }:
river.overrideAttrs (oldAttrs: {
  patches = (oldAttrs.patches or [ ]) ++ [ ./river-legacy-kde-decoration.patch ];
})
