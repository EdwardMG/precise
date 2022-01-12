" This plugin is based on an old plugin by this wonderful author:
" PreciseJump - script to ease on-screen motion
" version: 0.49 - 2011-03-26
" original author: Bartlomiej (email and last name removed for author
" privacy... it's been 10 years, he probably doesn't want to hear from you)

" Precise
" version: 0.00 - 2022-01-11
" author: EDEDED
" desc: I've modified the original concept here and adjusted ergonomics to my
" convenience. Namely instead of thinking about motions, I'm thinking about
" text objects and things to do to them, in as abstract and extensible a way
" as I can be bothered with
"
" I have made basically no modification to the filter and interface part of
" this program, only the way that targets are generated and the way that they
" are acted upon

let g:Precise_target_keys = 'bcdefghijklmnorstuwx'
hi PreciseTarget ctermfg=yellow ctermbg=red cterm=bold gui=bold guibg=Red guifg=yellow
let g:Precise_match_target_hi = 'PreciseTarget'

let s:index_to_key = split(g:Precise_target_keys, '\zs')
let s:key_to_index = {}

let index = 0
for i in s:index_to_key
    let s:key_to_index[i] = index
    let index += 1
endfor


" split 'list' into groups (list of lists) of
" 'group_size' length
fu! s:SplitListIntoGroups(list, group_size)
    let groups = []
    let i = 0
    while i < len(a:list)
        call add(groups, a:list[i : i + a:group_size - 1])
        let i += a:group_size
    endwhile
    return groups
endfu

fu! s:GetLinesFromCoordList(list)
    let lines_seen = {}
    let lines_no = []
    for [l, c] in a:list
        if !has_key(lines_seen, l)
            call add(lines_no, l)
            let lines_seen[l] = 1
        endif
    endfor
    return lines_no
endfu

fu! s:CreateHighlightRegex(coords)
    let tmp = []
    for [l, c] in s:Flatten(a:coords)
        call add(tmp, '\%' . l . 'l\%' . c . 'c')
    endfor
    return join(tmp, '\|')
endfu

fu! s:Flatten(list)
    let res = []
    for elem in a:list
        call extend(res, elem)
    endfor
    return res
endfu

" this is the main tricky piece and the whole reason to borrow this plugin
" get a list of coordinates groups [   [ [1,2], [2,5] ], [ [2,2] ]  ]
" get a list of coordinates groups [   [ [1,2], [2,5] ]  ]
fu! s:AskForTarget(groups) abort
    let single_group = ( len(a:groups) == 1 ? 1 : 0 )

    " how many targets there is
    let targets_count = single_group ? len(a:groups[0]) : len(a:groups)

    if single_group && targets_count == 1
        return a:groups[0][0]
    endif

    " which lines need to be changed
    let lines = s:GetLinesFromCoordList(s:Flatten(a:groups))

    " creating copy of lines to be changed
    let lines_with_markers = {}
    for l in lines
        let lines_with_markers[l] = split(getline(l), '\zs')
    endfor

   " adding markers to lines
    let gr = 0 " group no
    for group in a:groups
        let el = 0 " element in group no
        for [l, c] in group
            " highlighting with group mark or target mark
            let lines_with_markers[l][c - 1] = s:index_to_key[ single_group ? el : gr ]
            let el += 1
        endfor
        let gr += 1
    endfor

   " create highlight
    let hi_regex = s:CreateHighlightRegex(a:groups)

    "
    let user_char = ''
    let modifiable = &modifiable
    let readonly = &readonly

    try
        let match_id = matchadd(g:Precise_match_target_hi, hi_regex, -1)
        if modifiable == 0
            silent setl modifiable
        endif
        if readonly == 1
            silent setl noreadonly
        endif

        for [lnum, line_arr] in items(lines_with_markers)
            call setline(lnum, join(line_arr, ''))
        endfor
        redraw
        if single_group
            echo "target char>"
        else
            echo "group char>"
        endif
        let user_char = nr2char( getchar() )
        redraw
    finally
        normal! u
        normal 

        call matchdelete(match_id)
        redraw
        if modifiable == 0
            silent setl nomodifiable
        endif
        if readonly == 1
            silent setl readonly
        endif

        if ! has_key(s:key_to_index, user_char) || s:key_to_index[user_char] >= targets_count
            return []
        else
            if single_group
                if ! has_key(s:key_to_index, user_char)
                    return []
                else
                    return a:groups[0][ s:key_to_index[user_char] ]  " returning coordinates
                endif
            else
                return s:AskForTarget( [ a:groups[ s:key_to_index[user_char] ] ] )
            endif
        endif
    endtry
endfu

fu! s:LinesAllSequential()
    return filter( range(line('w0'), line('w$')), 'foldclosed(v:val) == -1' )
endfu

fu! Precise(find_targets, action)
    let group_size = len(s:index_to_key)
    let lnums = s:LinesAllSequential()

    let targets = a:find_targets(lnums)
    if len(targets) == 0
        echo "No targets found"
        return
    endif

    let groups = s:SplitListIntoGroups( targets, group_size )

    " too many targets; showing only first ones
    if len(groups) > group_size
        echo "Showing only first targets"
        let groups = groups[0 : group_size - 1]
    endif

    let coords = s:AskForTarget(groups)

    if len(coords) != 2
        echo "Cancelled"
        return
    else
        call a:action(coords[0], coords[1])
    endif
endfu


" Example Config
" --------------

" function returns list of places ([line, column]),
" that match regular expression 're'
" in lines of numbers from list 'line_numbers'
fu! s:_FindTargetsByRegexp(re, line_numbers)
    let targets = []
    for l in a:line_numbers
        let n = 1
        let match_start = match(getline(l), a:re, 0, 1)
        while match_start != -1
            call add(targets, [l, match_start + 1])
            let n += 1
            let match_start = match(getline(l), a:re, 0, n)
        endwhile
    endfor
    return targets
endfu
let FindTargetsByRegexp = { re -> { lnums -> s:_FindTargetsByRegexp(re, lnums) }}

let FindLineTargets     = FindTargetsByRegexp('^\zs.')
let FindWordTargets     = FindTargetsByRegexp('\<.')
let FindEndWordTargets  = FindTargetsByRegexp('.\>')
let FindConstantTargets = FindTargetsByRegexp('\<\u')
let FindBracketTargets  = FindTargetsByRegexp('[([{]')
let FindQuoteTargets    = FindTargetsByRegexp('[''"]')

fu! s:_FindParagraphTargets(line_numbers)
    let targets = []
    for l in a:line_numbers
        if match(getline(l), '^.', 0, 1) != -1 && match(getline(l-1), '^$', 0, 1) != -1
            call add(targets, [l, 1])
        endif
    endfor
    return targets
endfu
let FindParagraphTargets = { lnums -> s:_FindParagraphTargets(lnums)}

fu! s:_GoAndComeBack(l, c, keys)
    let p = getcurpos()
    call cursor(a:l, a:c)
    exe "normal! ".a:keys
    call setpos('.', p)
endfu

fu! s:_UnsafeGoAndComeBack(l, c, keys)
    let p = getcurpos()
    call cursor(a:l, a:c)
    exe "normal ".a:keys
    call setpos('.', p)
endfu

fu! s:_GoAndComeBackAndDoMore(l, c, keys, bkeys)
    let p = getcurpos()
    call cursor(a:l, a:c)
    exe "normal! ".a:keys
    call setpos('.', p)
    exe "normal! ".a:bkeys
endfu

fu! s:_UnsafeGoAndComeBackAndDoMore(l, c, keys, bkeys)
    let p = getcurpos()
    call cursor(a:l, a:c)
    exe "normal ".a:keys
    call setpos('.', p)
    exe "normal! ".a:bkeys
endfu

fu! s:_GoAndFeedKeys(l, c, keys)
    call cursor(a:l, a:c)
    call feedkeys(a:keys, 'n')
endfu

fu! s:_UnsafeGoAndFeedKeys(l, c, keys)
    call cursor(a:l, a:c)
    call feedkeys(a:keys, 't')
endfu

let GoAndComeBack                = { keys -> { l, c -> s:_GoAndComeBack(l, c, keys)}}
let GoAndComeBackAndDoMore       = { keys, bkeys -> { l, c -> s:_GoAndComeBackAndDoMore(l, c, keys, bkeys)}}
let UnsafeGoAndComeBack          = { keys -> { l, c -> s:_UnsafeGoAndComeBack(l, c, keys)}}
let UnsafeGoAndComeBackAndDoMore = { keys, bkeys -> { l, c -> s:_UnsafeGoAndComeBackAndDoMore(l, c, keys, bkeys)}}
let GoAndFeedKeys                = { keys -> { l, c -> s:_GoAndFeedKeys(l, c, keys)}}
let UnsafeGoAndFeedKeys          = { keys -> { l, c -> s:_UnsafeGoAndFeedKeys(l, c, keys)}}

let DeleteLine      = GoAndComeBack('dd')
let DeleteWord      = GoAndComeBack('dw')
let DeleteEndWord   = GoAndComeBack('vbd')
let DeleteParagraph = GoAndComeBack('dap')

let YankLine      = GoAndComeBack('yy')
let YankWord      = GoAndComeBack('yw')
let YankEndWord   = GoAndComeBack('vby')
let YankParagraph = GoAndComeBack('yap')

let PasteLine      = GoAndComeBackAndDoMore('yy', 'p')
let PasteWord      = GoAndComeBackAndDoMore('yw', 'p')
let PasteEndWord   = GoAndComeBackAndDoMore('vby', 'p')
let PasteParagraph = GoAndComeBackAndDoMore('yap', 'p')

let PullLine      = GoAndComeBackAndDoMore('dd', 'p')
let PullWord      = GoAndComeBackAndDoMore('dw', 'p')
let PullEndWord   = GoAndComeBackAndDoMore('vbd', 'p')
let PullParagraph = GoAndComeBackAndDoMore('dap', 'p')

let ChangeLine      = GoAndFeedKeys('cc')
let ChangeWord      = GoAndFeedKeys('cw')
let ChangeEndWord   = GoAndFeedKeys('vbc')
let ChangeParagraph = GoAndFeedKeys('cip')

" targets is a smart and cool plugin
if exists("g:loaded_targets")
    let DeleteBracket = UnsafeGoAndComeBack("dib")
    let YankBracket   = UnsafeGoAndComeBack("yib")
    let PasteBracket  = UnsafeGoAndComeBackAndDoMore("yib", 'p')
    let PullBracket   = UnsafeGoAndComeBackAndDoMore("dib", 'p')
    let ChangeBracket = UnsafeGoAndFeedKeys('cib')

    let DeleteQuote = UnsafeGoAndComeBack("diq")
    let YankQuote   = UnsafeGoAndComeBack("yiq")
    let PasteQuote  = UnsafeGoAndComeBackAndDoMore("yiq", 'p')
    let PullQuote   = UnsafeGoAndComeBackAndDoMore("diq", 'p')
    let ChangeQuote = UnsafeGoAndFeedKeys('ciq')
else
    let DeleteBracket = GoAndComeBack("ld/[)\\]}]\<CR>")
    let YankBracket   = GoAndComeBack("ly/[)\\]}]\<CR>")
    let PasteBracket  = GoAndComeBackAndDoMore("ly/[)\\]}]\<CR>", 'p')
    let PullBracket   = GoAndComeBackAndDoMore("ld/[)\\]}]\<CR>", 'p')
    let ChangeBracket = GoAndFeedKeys('lc/[)\]}]')

    let DeleteQuote = GoAndComeBack("ld/['\"]\<CR>")
    let YankQuote   = GoAndComeBack("ly/['\"]\<CR>")
    let PasteQuote  = GoAndComeBackAndDoMore("ly/['\"]\<CR>", 'p')
    let PullQuote   = GoAndComeBackAndDoMore("ld/['\"]\<CR>", 'p')
    let ChangeQuote = GoAndFeedKeys('lc/[''"]')
endif

" literal for <right>
let Jump = UnsafeGoAndFeedKeys('OC')

nno smb :call Precise(FindBracketTargets, function('cursor'))<cr>
nno scb :call Precise(FindBracketTargets, ChangeBracket)<cr>
nno sdb :call Precise(FindBracketTargets, DeleteBracket)<cr>
nno syb :call Precise(FindBracketTargets, YankBracket)<cr>
nno spb :call Precise(FindBracketTargets, PasteBracket)<cr>
nno slb :call Precise(FindBracketTargets, PullBracket)<cr>

nno smq :call Precise(FindQuoteTargets, function('cursor'))<cr>
nno scq :call Precise(FindQuoteTargets, ChangeQuote)<cr>
nno sdq :call Precise(FindQuoteTargets, DeleteQuote)<cr>
nno syq :call Precise(FindQuoteTargets, YankQuote)<cr>
nno spq :call Precise(FindQuoteTargets, PasteQuote)<cr>
nno slq :call Precise(FindQuoteTargets, PullQuote)<cr>

nno smw :call Precise(FindWordTargets, function('cursor'))<cr>
nno scw :call Precise(FindWordTargets, ChangeWord)<cr>
nno sdw :call Precise(FindWordTargets, DeleteWord)<cr>
nno syw :call Precise(FindWordTargets, YankWord)<cr>
nno spw :call Precise(FindWordTargets, PasteWord)<cr>
nno slw :call Precise(FindWordTargets, PullWord)<cr>

nno smc :call Precise(FindConstantTargets, function('cursor'))<cr>
nno scc :call Precise(FindConstantTargets, ChangeWord)<cr>
nno sdc :call Precise(FindConstantTargets, DeleteWord)<cr>
nno syc :call Precise(FindConstantTargets, YankWord)<cr>
nno spc :call Precise(FindConstantTargets, PasteWord)<cr>
nno slc :call Precise(FindConstantTargets, PullWord)<cr>

nno sj :call Precise(FindConstantTargets, Jump)<cr>

nno sme :call Precise(FindEndWordTargets, function('cursor'))<cr>
nno sce :call Precise(FindEndWordTargets, ChangeEndWord)<cr>
nno sde :call Precise(FindEndWordTargets, DeleteEndWord)<cr>
nno sye :call Precise(FindEndWordTargets, YankEndWord)<cr>
nno spe :call Precise(FindEndWordTargets, PasteEndWord)<cr>
nno sle :call Precise(FindEndWordTargets, PullEndWord)<cr>

nno sml :call Precise(FindLineTargets, function('cursor'))<cr>
nno scl :call Precise(FindLineTargets, ChangeLine)<cr>
nno sdl :call Precise(FindLineTargets, DeleteLine)<cr>
nno syl :call Precise(FindLineTargets, YankLine)<cr>
nno spl :call Precise(FindLineTargets, PasteLine)<cr>
nno sll :call Precise(FindLineTargets, PullLine)<cr>

nno smp :call Precise(FindParagraphTargets, function('cursor'))<cr>
nno scp :call Precise(FindParagraphTargets, ChangeParagraph)<cr>
nno sdp :call Precise(FindParagraphTargets, DeleteParagraph)<cr>
nno syp :call Precise(FindParagraphTargets, YankParagraph)<cr>
nno spp :call Precise(FindParagraphTargets, PasteParagraph)<cr>
nno slp :call Precise(FindParagraphTargets, PullParagraph)<cr>
