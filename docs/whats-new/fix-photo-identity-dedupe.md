# Both lines take effect once the server change in the same PR is deployed. The second covers every
# photo sent from this build on. A photo sent by an earlier build is removed for everyone when its
# tree's page has loaded in the same session and its match is unambiguous; otherwise it is removed
# on the phone only, as before (docs/errata-pending/photo-withdrawal-silent-no-op.md). Such a photo
# that is still public shows on its contributor's page again, and deleting it there now reaches the
# service; the same tap now works on your own photo that another of your phones sent.
A photo you took no longer counts twice on its tree's page, so the photo count matches the photos you see.
Deleting a photo you took now removes it for everyone, not only on your phone.
