# =============================================================================
#  tests/golden.route.tests.ps1  —  ルート分類 の期待入出力テーブル（層2 pending）
#
#  TODO Phase 1.3: Resolve-Route が src/ から純粋関数として抽出されたら、
#                  下記コメント内のアサーションを有効化して Write-TestPending を削除する。
#                  関数シグネチャ案: Resolve-Route([string]$Path, [string]$Method) -> pscustomobject
#                    .Kind  : 'status'|'elapsed'|'slide-state'|'lock-on'|'lock-steal'|'lock-off'|'slide'|'other'
#                    .Cmd   : string（Kind='slide' のときのみ有効、例: 'next'）
#                    .Valid : bool（Kind='slide' のときのみ有効）
#
#  対象ロジック（現状 src/com-handler.ps1 Watch-RunningPresentation にインライン）:
#    valid コマンド集合: next, prev, first, last, blackout, whiteout
#    （docs/01_characterization_spec.txt [F]）
# =============================================================================

Write-TestPending "[F] GET /status        -> kind=status"
# $r = Resolve-Route '/status' 'GET';       Assert-Equal 'status'      $r.Kind  '[F] /status GET'

Write-TestPending "[F] GET /elapsed       -> kind=elapsed"
# $r = Resolve-Route '/elapsed' 'GET';      Assert-Equal 'elapsed'     $r.Kind  '[F] /elapsed GET'

Write-TestPending "[F] GET /slide/state   -> kind=slide-state"
# $r = Resolve-Route '/slide/state' 'GET';  Assert-Equal 'slide-state' $r.Kind  '[F] /slide/state GET'

Write-TestPending "[F] POST /lock/on      -> kind=lock-on"
# $r = Resolve-Route '/lock/on' 'POST';     Assert-Equal 'lock-on'     $r.Kind  '[F] /lock/on POST'

Write-TestPending "[F] POST /lock/steal   -> kind=lock-steal"
# $r = Resolve-Route '/lock/steal' 'POST';  Assert-Equal 'lock-steal'  $r.Kind  '[F] /lock/steal POST'

Write-TestPending "[F] POST /lock/off     -> kind=lock-off"
# $r = Resolve-Route '/lock/off' 'POST';    Assert-Equal 'lock-off'    $r.Kind  '[F] /lock/off POST'

Write-TestPending "[F] POST /slide/next   -> kind=slide, cmd=next, valid=true"
# $r = Resolve-Route '/slide/next' 'POST';  Assert-Equal 'slide' $r.Kind '[F] /slide/next kind'
#                                           Assert-Equal 'next'  $r.Cmd  '[F] /slide/next cmd'
#                                           Assert-Equal $true   $r.Valid '[F] /slide/next valid'

Write-TestPending "[F] POST /slide/zzz    -> kind=slide, cmd=zzz, valid=false"
# $r = Resolve-Route '/slide/zzz' 'POST';   Assert-Equal 'slide' $r.Kind  '[F] /slide/zzz kind'
#                                           Assert-Equal 'zzz'   $r.Cmd   '[F] /slide/zzz cmd'
#                                           Assert-Equal $false  $r.Valid  '[F] /slide/zzz valid'

Write-TestPending "[F] GET  /slide/next   -> kind=other (POST 以外は slide 対象外)"
# $r = Resolve-Route '/slide/next' 'GET';   Assert-Equal 'other' $r.Kind  '[F] /slide/next GET'

Write-TestPending "[F] GET  /unknown      -> kind=other"
# $r = Resolve-Route '/unknown' 'GET';      Assert-Equal 'other' $r.Kind  '[F] /unknown GET'
