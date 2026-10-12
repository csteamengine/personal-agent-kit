import type { Register } from 'claude-code'

const HEADER = ['#ff9e3d', '#ff9e3d', '#ffb366', '#ffb366'] as const
const BOLD = '#ff9e3d'
const CODE = '#7dcfff'

type Segment =
  | { kind: 'header'; level: number; text: string }
  | { kind: 'md'; text: string }
  | { kind: 'line'; text: string }
  | { kind: 'gap' }

const isBlank = (line: string) => line.trim() === ''

const split = (text: string): Segment[] => {
  const out: Segment[] = []
  let md: string[] = []
  let isFenced = false

  // Markdown drops blank lines at the edges of each chunk, so carry them
  // across segment boundaries as explicit gaps.
  const gap = () => {
    if (out.length > 0 && out[out.length - 1].kind !== 'gap') {
      out.push({ kind: 'gap' })
    }
  }

  const flush = () => {
    let start = 0
    let end = md.length
    while (start < end && isBlank(md[start])) start++
    while (end > start && isBlank(md[end - 1])) end--
    if (start > 0) gap()
    if (start < end) out.push({ kind: 'md', text: md.slice(start, end).join('\n') })
    if (end < md.length && start < end) gap()
    md = []
  }

  for (const line of text.split('\n')) {
    if (/^\s*(```|~~~)/.test(line)) {
      isFenced = !isFenced
      md.push(line)
      continue
    }
    if (isFenced || /^\s*\|/.test(line)) {
      md.push(line)
      continue
    }
    const h = /^(#{1,6})\s+(.*\S)\s*$/.exec(line)
    if (h) {
      flush()
      out.push({ kind: 'header', level: h[1].length, text: h[2] })
    } else if (/\*\*.+?\*\*/.test(line) && !/^\s*([-*>]|\d+\.)\s/.test(line) && !line.includes('](')) {
      flush()
      out.push({ kind: 'line', text: line })
    } else {
      md.push(line)
    }
  }
  flush()
  if (out.length > 0 && out[out.length - 1].kind === 'gap') out.pop()

  return out
}

export const register: Register = on => {
  on('ui.render', { component: 'AssistantMessage' }, ($, e, next) => {
    if (!/(^|\n)#{1,6}\s|\*\*.+?\*\*/.test(e.props.text)) {
      return next(e)
    }

    const { Box, Text, Markdown } = $.ui.resolve(e)

    const runs = (s: string) =>
      s.split(/(\*\*.+?\*\*|`[^`]+`)/).map((part, i) => {
        if (part.startsWith('**') && part.endsWith('**') && part.length > 4) {
          return (
            <Text key={`r${i}`} bold color={BOLD}>
              {part.slice(2, -2)}
            </Text>
          )
        }
        if (part.startsWith('`') && part.endsWith('`') && part.length > 2) {
          return (
            <Text key={`r${i}`} color={CODE}>
              {part.slice(1, -1)}
            </Text>
          )
        }

        return <Text key={`r${i}`}>{part}</Text>
      })

    return (
      <Box flexDirection="column">
        {split(e.props.text).map((s, i) => {
          if (s.kind === 'header') {
            return (
              <Text
                key={`h${i}`}
                bold
                underline={s.level === 1}
                color={HEADER[Math.min(s.level, 4) - 1]}
              >
                {s.text}
              </Text>
            )
          }
          if (s.kind === 'gap') {
            return <Text key={`g${i}`}> </Text>
          }
          if (s.kind === 'md') {
            return <Markdown key={`m${i}`} text={s.text} />
          }

          return <Text key={`r${i}`}>{runs(s.text)}</Text>
        })}
      </Box>
    )
  })
}
