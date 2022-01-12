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


" function returns list of places ([line, column]),
" that match regular expression 're'
" in lines of numbers from list 'line_numbers'
function! s:FindTargets(re, line_numbers)
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
endfunction

" split 'list' into groups (list of lists) of
" 'group_size' length
function! s:SplitListIntoGroups(list, group_size)
    let groups = []
    let i = 0
    while i < len(a:list)
        call add(groups, a:list[i : i + a:group_size - 1])
        let i += a:group_size
    endwhile
    return groups
endfunction

function! s:GetLinesFromCoordList(list)
    let lines_seen = {}
    let lines_no = []
    for [l, c] in a:list
        if !has_key(lines_seen, l)
            call add(lines_no, l)
            let lines_seen[l] = 1
        endif
    endfor
    return lines_no
endfunction

function! s:CreateHighlightRegex(coords)
    let tmp = []
    for [l, c] in s:Flatten(a:coords)
        call add(tmp, '\%' . l . 'l\%' . c . 'c')
    endfor
    return join(tmp, '\|')
endfunction

function! s:Flatten(list)
    let res = []
    for elem in a:list
        call extend(res, elem)
    endfor
    return res
endfunction

" this is the main tricky piece and the whole reason to borrow this plugin
" get a list of coordinates groups [   [ [1,2], [2,5] ], [ [2,2] ]  ]
" get a list of coordinates groups [   [ [1,2], [2,5] ]  ]
function! s:AskForTarget(groups) abort
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
endfunction

function! s:LinesAllSequential()
    return filter( range(line('w0'), line('w$')), 'foldclosed(v:val) == -1' )
endfunction

function! Precise(find_targets, action)
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
endfunction

let FindLineTargets = { lnums -> s:FindTargets('^\zs.', lnums) }
let FindWordTargets = { lnums -> s:FindTargets('\<.', lnums) }
let FindEndWordTargets = { lnums -> s:FindTargets('.\>', lnums) }

function! FindParagraphTargets(line_numbers)
    let targets = []
    for l in a:line_numbers
        if match(getline(l), '^.', 0, 1) != -1 && match(getline(l-1), '^$', 0, 1) != -1
            call add(targets, [l, 1])
        endif
    endfor
    return targets
endfunction

fu! DeleteLine(l,_)
    exe "normal! :".a:l."d\<CR>\<C-o>"
endfu

fu! DeleteParagraph(l,c)
    let p = getcurpos()
    call cursor(a:l,a:c)
    exe "normal! dap"
    call setpos('.', p)
endfu

fu! DeleteWord(l,c)
    let p = getcurpos()
    call cursor(a:l,a:c)
    exe "normal! dw"
    call setpos('.', p)
endfu

fu! ChangeParagraph(l,c)
    let p = getcurpos()
    call cursor(a:l,a:c)
    call feedkeys('cip', 'n')
endfu

fu! ChangeWord(l,c)
    call cursor(a:l,a:c)
    call feedkeys('cw', 'n')
endfu

fu! ChangeLine(l,c)
    call cursor(a:l,a:c)
    call feedkeys('cc', 'n')
endfu

fu! ChangeEndWord(l,c)
    let p = getcurpos()
    call cursor(a:l,a:c)
    call feedkeys('vbc', 'n')
endfu

fu! DeleteEndWord(l,c)
    let p = getcurpos()
    call cursor(a:l,a:c)
    exe "normal! vbd"
    call setpos('.', p)
endfu

nno smw :call Precise(FindWordTargets, function('cursor'))<cr>
nno scw :call Precise(FindWordTargets, function('ChangeWord'))<cr>
nno sdw :call Precise(FindWordTargets, function('DeleteWord'))<cr>

nno sme :call Precise(FindEndWordTargets, function('cursor'))<cr>
nno sce :call Precise(FindEndWordTargets, function('ChangeEndWord'))<cr>
nno sde :call Precise(FindEndWordTargets, function('DeleteEndWord'))<cr>

nno sml :call Precise(FindLineTargets, function('cursor'))<cr>
nno scl :call Precise(FindLineTargets, function('ChangeLine'))<cr>
nno sdl :call Precise(FindLineTargets, function('DeleteLine'))<cr>

nno smp :call Precise(function('FindParagraphTargets'), function('cursor'))<cr>
nno scp :call Precise(function('FindParagraphTargets'), function('ChangeParagraph'))<cr>
nno sdp :call Precise(function('FindParagraphTargets'), function('DeleteParagraph'))<cr>


" this is for limiting lines searched in hopes of not triggering groups, I
" don't really care
" function! s:LinesInRange(lines_prev, lines_next)
"     let all_lines = filter( range(line('w0'), line('w$')), 'foldclosed(v:val) == -1' )
"     let current = index(all_lines, line('.'))

"     let lines_prev = a:lines_prev == -1 ? current : a:lines_prev
"     let lines_next = a:lines_next == -1 ? len(all_lines) : a:lines_next

"     let lines_prev_i   = max( [0, current - lines_prev] )
"     let lines_next_i   = min( [len(all_lines), current + lines_next] )

"     return all_lines[ lines_prev_i : lines_next_i ]
" endfunction

