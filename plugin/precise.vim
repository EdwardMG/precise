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

" Other ideas:
" md{letter} could instantly move you to a method starting with letter,
" otherwise give you the list of methods that start that way. md* would just
" list all of them

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

fu! Precise(find_targets, action, recur=1)
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

        " this doesn't quite work because of the undo dependency
        " if a:recur
        "     call Precise(a:find_targets, a:action, 1)
        " endif

        let g:Precise_repeat_targets = a:find_targets
        let g:Precise_repeat_action = a:action
        call repeat#set(':call Precise(g:Precise_repeat_targets, g:Precise_repeat_action)'."\<CR>")
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

fu! s:_FindIndentTargets(line_numbers)
    let targets = []
    for l in a:line_numbers
        let non_empty_line = match(getline(l), '^.', 0, 1) != -1
        let leading_whitespace = len(matchstr(getline(l), "^ *"))
        let next_leading_whitespace = len(matchstr(getline(l+1), "^ *"))
        if non_empty_line && leading_whitespace < next_leading_whitespace
            call add(targets, [l+1, 1])
        endif
    endfor
    return targets
endfu
let FindIndentTargets = { lnums -> s:_FindIndentTargets(lnums)}

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

let CommentLine      = UnsafeGoAndComeBack('gcc')
let CommentParagraph = UnsafeGoAndComeBack('gcip')

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

" in practice this would go in a vimrc
let g:indent_object = 1
if exists("g:indent_object")
    let DeleteIndent = UnsafeGoAndComeBack("dii")
    let YankIndent   = UnsafeGoAndComeBack("yii")
    let PasteIndent  = UnsafeGoAndComeBackAndDoMore("yii", 'p')
    let PullIndent   = UnsafeGoAndComeBackAndDoMore("dii", 'p')
    let ChangeIndent = UnsafeGoAndFeedKeys('cii')
    let CommentIndent = UnsafeGoAndComeBack('gcii')

    nno smi :call Precise(FindIndentTargets, function('cursor'))<cr>
    nno sci :call Precise(FindIndentTargets, ChangeIndent)<cr>
    nno sdi :call Precise(FindIndentTargets, DeleteIndent)<cr>
    nno syi :call Precise(FindIndentTargets, YankIndent)<cr>
    nno spi :call Precise(FindIndentTargets, PasteIndent)<cr>
    nno sli :call Precise(FindIndentTargets, PullIndent)<cr>
    nno ssi :call Precise(FindIndentTargets, CommentIndent)<cr>
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
nno ssl :call Precise(FindLineTargets, CommentLine)<cr>

nno smp :call Precise(FindParagraphTargets, function('cursor'))<cr>
nno scp :call Precise(FindParagraphTargets, ChangeParagraph)<cr>
nno sdp :call Precise(FindParagraphTargets, DeleteParagraph)<cr>
nno syp :call Precise(FindParagraphTargets, YankParagraph)<cr>
nno spp :call Precise(FindParagraphTargets, PasteParagraph)<cr>
nno slp :call Precise(FindParagraphTargets, PullParagraph)<cr>
nno ssp :call Precise(FindParagraphTargets, CommentParagraph)<cr>


fu! s:Setup()
ruby << RUBY

require 'date'
require 'json'

module Precise
  Ref = Struct.new(:v, :path, :lnum, :ref, :date, :pattern)
  LETTERS = 'bcdefghijklmnorstuwx'.split('')
  LETTER_PAIRS = LETTERS.product(LETTERS).map(&:join)

  Buffer = Struct.new(:name)
  def self.buffers
    bs = []
    Ev.getbufinfo.each do |b|
      next if b['listed'] == 0
      unless b['name'].empty?
        bs << Buffer.new(b['name'])
      end
    end
    bs
  end

  # expand this to get any sort of high level definition, like constants and
  # classes
  def self.get_defs p
    rs = []

    each_fl(p) do |l, lnum|
      if v = gen_def(l)
        rs << Ref.new(v, p, lnum, nil, nil)
      end
    end
    if rs.length > LETTERS.length
      rs.each_with_index {|r, i| r.ref = LETTER_PAIRS[i] }
    else
      rs.each_with_index {|r, i| r.ref = LETTERS[i] }
    end
    rs
  end

  def self.gen_def l
    if l.match?(/^\s*(class|module|def) /) # ruby
      l.match(/^\s*(class|module|def) (self|)([A-z_0-9\.\?\!]*)/)[3]
    elsif l.match?(/^\s*function\s+([A-z_0-9]*)\(/) # js
      l.match(/^\s*function\s+([A-z_0-9]*)\(/)[1]
    elsif l.match?(/^\s*fu\!\s+([:A-z_0-9]*)\(/) # vim
      l.match(/^\s*fu\!\s+([:A-z_0-9]*)\(/)[1]
    elsif l.match?(/^\s*([A-Z_0-9]*)\s*=/) # constant
      l.match(/^\s*([A-Z_0-9]*)\s*=/)[1]
    end
  end

  SPACING = 40
  def self.display rs
    last_v = ' '
    rs = rs.sort_by(&:v).map do |r|
      if r.v[0] == last_v[0]
        "#{r.ref}   #{r.v[..SPACING-2]}"
      else
        last_v = r.v[0]
        "#{r.ref} #{r.v[..SPACING]}"
      end
    end

    height = `tput lines`.to_i
    half = rs.length / 2
    rs2 = []

    if half < height
      rs[..half].each.with_index(1) do |r, offset|
        spaces = ''
        spaces = ' ' * (SPACING + 5 - r.length) if SPACING + 5 - r.length > 0
        rs2 << "#{r}#{spaces} #{rs[half+offset]} "
      end
    else
      third = rs.length / 3
      rs[..third].each.with_index(1) do |r, offset|
        spaces = ''
        spaces = ' ' * (SPACING + 5 - r.length) if SPACING + 5 - r.length > 0
        ftr = "#{r}#{spaces} #{rs[third+offset]}"
        spaces2 = ' ' * (SPACING*2 + 5 - ftr.length) if SPACING*2 + 5 - ftr.length > 0
        rs2 << "#{r}#{spaces} #{rs[third+offset]} #{spaces2} #{rs[third*2+offset]}"
      end
    end
    $move_to_def_popup = Ev.popup_create(rs2, { title: '', padding: [1,1,1,1], line: 1, pos: 'topleft', scrollbar: 1 })
    # Ev.setbufvar( Ev.winbufnr( $move_to_def_popup ), '&filetype', 'markdown')
    # let s:N.SetFT = { ft -> { bufnr -> s:N.Snd([ setbufvar( winbufnr( bufnr ), '&filetype', ft), bufnr ]) } }
  end

  def self.get_ref rs
    inp = Ev.getcharstr
    inp += Ev.getcharstr if rs.length > LETTERS.length
    rs.find {|r| r.ref == inp}
  end

  def self.move
    rs = get_defs Vim::Buffer.current.name
    display rs
    Ex.redraw!
    r = get_ref rs
    Ev.popup_clear $move_to_def_popup
    return unless r
    Ex.edit r.path
    Ex.normal! "#{r.lnum}ggzt"
  end

  def self.each_fl(p, &block)
    File.open(p, "r").each_line.with_index(1, &block)
  end

  class EasyRef
    attr_accessor :es, :p, :f

    def initialize p, filter=nil
      @p  = p
      @es = ::EasyStorage.new(p)
      @f  = filter
    end

    def rs
      es.d
    end

    def add_current_line_with_label
      add Ev.expand("%:p"), Ev.line('.'), Ev.input('label: ')
    end

    def add_current_line
      add Ev.expand("%:p"), Ev.line('.')
    end

    def add path, lnum, label=nil
      Ex.write
      l = nil
      Precise.each_fl(path) do |f_l, f_lnum|
        if f_lnum == lnum
          l = f_l
          break
        end
      end
      label = gen_label(l, path, lnum) unless label
      pattern = gen_pattern(l)
      rs << Ref.new(label, path, lnum, nil, Date.today.to_s, pattern)
      es.save
    end

    def gen_pattern l
      if l.match?(/^\s*(class|module|def) /)
        l.match(/\s*((class|module|def)\s+(self|)([A-z_0-9\.\?\!]*))/)[1]
      elsif l.match?(/^\s*function\s+([A-z_0-9]*)\(/)
        l.match(/^(\s*function\s+([A-z_0-9]*)\()/)[1]
      elsif l.match?(/^\s*([A-Z_0-9]*)\s*=/)
        l.match(/^\s*([A-Z_0-9]*\s*=)/)[1]
      end
    end

    def gen_label l, path, lnum
      if l.match?(/^\s*(class|module|def) /)
        l.match(/^\s*(class|module|def) (self|)([A-z_0-9\.\?\!]*)/)[3]
      elsif l.match?(/^\s*function\s+([A-z_0-9]*)\(/)
        l.match(/^\s*function\s+([A-z_0-9]*)\(/)[1]
      elsif l.match?(/^\s*([A-Z_0-9]*)\s*=/)
        l.match(/^\s*([A-Z_0-9]*)\s*=/)[1]
      else
        path.split('/').last.split('.').first + ':' + lnum.to_s
      end
    end

    def filtered_refs
      return rs unless f
      rs.select &f
    end

    SPACING = 40
    def display
      Precise.display filtered_refs
    end

    def get_ref
      rs1 = filtered_refs
      inp = Ev.getcharstr
      inp += Ev.getcharstr if rs1.length > LETTERS.length
      rs1.find {|r| r.ref == inp}
    end

    def recalc_ref_codes
      rs1 = filtered_refs
      if rs1.length > LETTERS.length
        rs1.each_with_index {|r, i| r.ref = LETTER_PAIRS[i] }
      else
        rs1.each_with_index {|r, i| r.ref = LETTERS[i] }
      end
    end

    def move
      recalc_ref_codes
      display
      Ex.redraw!
      r = get_ref
      Ev.popup_clear $move_to_def_popup
      return unless r
      Ex.edit r.path
      if r.pattern
        r_lnum = nil
        Precise.each_fl(r.path) do |l, lnum|
          if l.include? r.pattern
            r_lnum = lnum
            break
          end
        end
        if r_lnum
          Ex.normal! "#{r_lnum}ggzt"
        else
          Ex.normal! "#{r.lnum}ggzt"
        end
      else
        Ex.normal! "#{r.lnum}ggzt"
      end
      # this doesn't seem to work for js?
      Ex.syn "sync fromstart"
      Ex.redraw!
    end
  end

  class DynamicRef
    attr_accessor :getter, :rs

    # getter is a lambda to populate refs
    def initialize getter
      @getter = getter
      @rs     = []
    end

    SPACING = 40
    def display
      Precise.display rs
    end

    def get_ref
      inp = Ev.getcharstr
      inp += Ev.getcharstr if rs.length > LETTERS.length
      rs.find {|r| r.ref == inp}
    end

    def recalc_ref_codes
      if rs.length > LETTERS.length
        rs.each_with_index {|r, i| r.ref = LETTER_PAIRS[i] }
      else
        rs.each_with_index {|r, i| r.ref = LETTERS[i] }
      end
    end

    def move
      @rs = @getter.call
      recalc_ref_codes
      display
      Ex.redraw!
      r = get_ref
      Ev.popup_clear $move_to_def_popup
      return unless r
      Ex.edit r.path
      if r.pattern
        r_lnum = nil
        Precise.each_fl(r.path) do |l, lnum|
          if l.include? r.pattern
            r_lnum = lnum
            break
          end
        end
        if r_lnum
          Ex.normal! "#{r_lnum}ggzt"
        else
          Ex.normal! "#{r.lnum}ggzt"
        end
      else
        Ex.normal! "#{r.lnum}ggzt"
      end
      # this doesn't seem to work for js?
      Ex.syn "sync fromstart"
      Ex.redraw!
    end
  end

  def self.initialize_mappings klass, key
    Ex.nno "m#{key.downcase}",  ":ruby Precise::#{klass}.move<CR>"
    Ex.nno "m'#{key.downcase}", ":ruby Precise::#{klass}.add_current_line_with_label<CR>"
    Ex.nno "m#{key.upcase}",    ":ruby Precise::#{klass}.add_current_line<CR>"
  end

  QuickRef = EasyRef.new(ENV["HOME"]+"/.quickrefvim")
  initialize_mappings "QuickRef", 'q'

  TempRef  = EasyRef.new(ENV["HOME"]+"/.temprefvim", ->(r) { Date.parse(r.date) > (Date.today - 14) })
  initialize_mappings "TempRef",  't'

  # intent of scratchref is to have something very rough for messy workflows
  # which you can copy lines from if you want to keep some or run g/blah/d
  # commands to filter down after building a bunch
  # ScratchRef = EasyRef.new(ENV["HOME"]+"/.scratchrefvim")
  # initialize_mappings "ScratchRef",  'm'

  def self.clear_scratch_ref
    if File.exist? ScratchRef.p
      File.write ScratchRef.p, ""
      ScratchRef.es.load
    end
  end

  Ex.command "ClearScratchRef :ruby Precise.clear_scratch_ref"

  # EgVimPlugins = DynamicRef.new(
  #   -> () {
  #     Dir[ENV["HOME"] + "/.vim/pack/eg/opt/**/plugin/*.vim"].map do |p|
  #       Precise::Ref.new(p.split('/').last.split('.')[0], p, 1, nil, Date.today.to_s, nil)
  #     end
  #   }
  # )
  # Ex.nno "mv",  ":ruby Precise::EgVimPlugins.move<CR>"

  #  Precise::EgAnki = Precise::DynamicRef.new(
  #    -> () {
  #      rs = []
  #      Dir[ENV["HOME"] + "/lol/src/**/*.js"].each do |p|
  #        File.open(p, "r").each_line.with_index(1) do |l, lnum|
  #          if l.match?(/^\s*function\s+([A-z_0-9]*)\(/)
  #            label = l.match(/^\s*function\s+([A-z_0-9]*)\(/)[1]
  #            rs << Precise::Ref.new(label, p, lnum, nil, nil, nil)
  #          end
  #        end
  #      end
  #      rs
  #    }
  #  )
  #  Ex.nno "ma",  ":ruby Precise::EgAnki.move<CR>"
  #
  #  Precise::EgLL = Precise::DynamicRef.new(
  #    -> () {
  #      rs = []
  #      Dir[ENV["HOME"] + "/egapps/javascript/language_learning/js/**/*.js"].each do |p|
  #        File.open(p, "r").each_line.with_index(1) do |l, lnum|
  #          if l.match?(/^\s*function\s+([A-z_0-9]*)\(/)
  #            fn = p.split('/').last.split('.').first + '#'
  #            label = fn + l.match(/^\s*function\s+([A-z_0-9]*)\(/)[1]
  #            rs << Precise::Ref.new(label, p, lnum, nil, nil, nil)
  #          end
  #        end
  #      end
  #      rs
  #    }
  #  )
  #  Ex.nno "ml",  ":ruby Precise::EgLL.move<CR>"

Precise::Markdown = Precise::DynamicRef.new(
  -> () {
    rs = []
    Precise.buffers.select {|b| b.name.end_with? '.md' }.each do |b|
      p = b.name
      lines = File.readlines(p, chomp: true)
      lines.each.with_index(1) do |l, lnum|
        if l.match?(/^#+ /)
          label = l
          rs << Precise::Ref.new(label, p, lnum, nil, nil, nil)
        elsif l.match?(/^``` /)
          label = l[4..]
          rs << Precise::Ref.new(label, p, lnum, nil, nil, nil)
        elsif l.match?(/^[-=]+$/)
          label = lines[lnum-2]
          rs << Precise::Ref.new(label, p, lnum-1, nil, nil, nil)
        end
      end
    end
    rs
  }
)
Ex.nno "mm",  ":ruby Precise::Markdown.move<CR>"

Precise::EgCd = Precise::DynamicRef.new(
  -> () {
    Dir["#{Ev.expand("%:h")}/**"].select {|p| File.directory? p }.map do |p|
      Precise::Ref.new(p.split('/').last, p, 1, nil, Date.today.to_s, nil)
    end
  }
)
Ex.nno "cd",  ":ruby Precise::EgCd.move<CR>"

Precise::EgCf = Precise::DynamicRef.new(
  -> () {
    Dir["#{Ev.expand("%:h")}/**"].select {|p| !File.directory? p }.map do |p|
      Precise::Ref.new(p.split('/').last, p, 1, nil, Date.today.to_s, nil)
    end
  }
)
Ex.nno "cf",  ":ruby Precise::EgCf.move<CR>"

Precise::EgCb = Precise::DynamicRef.new(
  -> () {
    Precise.buffers.map do |p|
      Precise::Ref.new(p.name.split('/').last, p.name, 1, nil, Date.today.to_s, nil)
    end
  }
)
Ex.nno "cb",  ":ruby Precise::EgCb.move<CR>"

Precise::EgMf = Precise::DynamicRef.new(
  -> () {
    rs = []
    Precise.buffers
    .select {|b| ['rb', 'js', 'vim'].include?(b.name.split('.').last) && File.exist?(b.name) }
    .each do |b|
      p = b.name

      File.open(p, "r").each_line.with_index(1) do |l, lnum|
        md = l.match(/^\s*function\s+([A-z_0-9]*)\(/) || l.match(/^\s*def\s+([A-z_0-9\.]*)/)
        if md
          fn = p.split('/').last.split('.').first + '#'
          label = fn + md[1]
          rs << Precise::Ref.new(label, p, lnum, nil, nil, nil)
        end
      end
    end
    rs
  }
)
Ex.nno "mf",  ":ruby Precise::EgMf.move<CR>"

Precise::EgMa = Precise::DynamicRef.new(
  -> () {
    rs = []
    Ev.argv.select {|p| ['rb', 'js', 'vim'].include?(p.split('.').last) && File.exist?(p) }
    .each do |p|

      File.open(p, "r").each_line.with_index(1) do |l, lnum|
        md = l.match(/^\s*function\s+([A-z_0-9]*)\(/) || l.match(/^\s*def\s+([A-z_0-9\.]*)/)
        if md
          fn = p.split('/').last.split('.').first + '#'
          label = fn + md[1]
          rs << Precise::Ref.new(label, p, lnum, nil, nil, nil)
        end
      end
    end
    rs
  }
)
# use with commands like :arga and :argd (default current buffer for arga, argd will take a pattern)
Ex.nno "ma",  ":ruby Precise::EgMa.move<CR>"

end
RUBY
endfu

call s:Setup()

nno md :ruby Precise.move<CR>
