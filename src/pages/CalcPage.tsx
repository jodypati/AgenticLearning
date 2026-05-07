import { useCallback, useState } from 'react'
import './CalcPage.css'

type Op = '+' | '-' | '*' | '/'

function applyOp(a: number, b: number, op: Op): number {
  switch (op) {
    case '+':
      return a + b
    case '-':
      return a - b
    case '*':
      return a * b
    case '/':
      return b === 0 ? NaN : a / b
    default:
      return b
  }
}

function formatResult(n: number): string {
  if (Number.isNaN(n) || !Number.isFinite(n)) {
    return 'Error'
  }
  return String(parseFloat(n.toPrecision(12)))
}

export default function CalcPage() {
  const [display, setDisplay] = useState('0')
  const [acc, setAcc] = useState<number | null>(null)
  const [pendingOp, setPendingOp] = useState<Op | null>(null)
  const [startsNewNumber, setStartsNewNumber] = useState(false)

  const resetAll = useCallback(() => {
    setDisplay('0')
    setAcc(null)
    setPendingOp(null)
    setStartsNewNumber(false)
  }, [])

  const inputDigit = useCallback((digit: string) => {
    setDisplay((prev) => {
      if (prev === 'Error') {
        return digit === '.' ? '0.' : digit
      }
      if (startsNewNumber) {
        setStartsNewNumber(false)
        return digit === '.' ? '0.' : digit
      }
      if (digit === '.' && prev.includes('.')) {
        return prev
      }
      if (prev === '0' && digit !== '.') {
        return digit
      }
      return prev + digit
    })
  }, [startsNewNumber])

  const inputOp = useCallback(
    (op: Op) => {
      setDisplay((prevStr) => {
        if (prevStr === 'Error') {
          return prevStr
        }
        const current = parseFloat(prevStr)

        if (acc !== null && pendingOp !== null && !startsNewNumber) {
          const result = applyOp(acc, current, pendingOp)
          if (Number.isNaN(result)) {
            setAcc(null)
            setPendingOp(op)
            setStartsNewNumber(true)
            return 'Error'
          }
          setAcc(result)
          setPendingOp(op)
          setStartsNewNumber(true)
          return formatResult(result)
        }

        setAcc(current)
        setPendingOp(op)
        setStartsNewNumber(true)
        return prevStr
      })
    },
    [acc, pendingOp, startsNewNumber],
  )

  const equals = useCallback(() => {
    if (pendingOp === null || acc === null) {
      return
    }
    setDisplay((prevStr) => {
      if (prevStr === 'Error') {
        return prevStr
      }
      const current = parseFloat(prevStr)
      const result = applyOp(acc, current, pendingOp)
      setAcc(null)
      setPendingOp(null)
      setStartsNewNumber(true)
      if (Number.isNaN(result)) {
        return 'Error'
      }
      return formatResult(result)
    })
  }, [acc, pendingOp])

  const backspace = useCallback(() => {
    if (startsNewNumber) {
      return
    }
    setDisplay((prev) => {
      if (prev === 'Error') {
        return '0'
      }
      if (prev.length <= 1) {
        return '0'
      }
      const next = prev.slice(0, -1)
      return next === '' || next === '-' ? '0' : next
    })
  }, [startsNewNumber])

  const onKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      const { key } = e
      if (/^[0-9]$/.test(key)) {
        e.preventDefault()
        inputDigit(key)
        return
      }
      if (key === '.') {
        e.preventDefault()
        inputDigit('.')
        return
      }
      if (key === 'Enter' || key === '=') {
        e.preventDefault()
        equals()
        return
      }
      if (key === 'Escape') {
        e.preventDefault()
        resetAll()
        return
      }
      if (key === 'Backspace') {
        e.preventDefault()
        backspace()
        return
      }
      const opMap: Record<string, Op> = {
        '+': '+',
        '-': '-',
        '*': '*',
        '/': '/',
      }
      if (key in opMap) {
        e.preventDefault()
        inputOp(opMap[key]!)
      }
    },
    [inputDigit, equals, resetAll, backspace, inputOp],
  )

  return (
    <section
      className="calc-page"
      onKeyDown={onKeyDown}
      tabIndex={0}
      aria-label="Kalkulator"
    >
      <div className="calc-page__intro">
        <h1>Kalkulator</h1>
        <p>
          Perhitungan cepat untuk kebutuhan kasir. Gunakan tombol atau
          papan ketik (angka, + − × /, Enter, Escape, Backspace).
        </p>
      </div>

      <div
        className="calc-calculator"
        role="application"
        aria-label="Kalkulator POS"
      >
        <div
          className="calc-calculator__display"
          aria-live="polite"
          aria-atomic="true"
        >
          {display}
        </div>
        <div className="calc-calculator__keys">
          <button
            type="button"
            className="calc-key calc-key--muted"
            onClick={resetAll}
          >
            AC
          </button>
          <button
            type="button"
            className="calc-key calc-key--muted"
            onClick={backspace}
          >
            ←
          </button>
          <button
            type="button"
            className="calc-key calc-key--accent"
            onClick={() => inputOp('/')}
          >
            ÷
          </button>
          <button
            type="button"
            className="calc-key calc-key--accent"
            onClick={() => inputOp('*')}
          >
            ×
          </button>

          <button type="button" className="calc-key" onClick={() => inputDigit('7')}>
            7
          </button>
          <button type="button" className="calc-key" onClick={() => inputDigit('8')}>
            8
          </button>
          <button type="button" className="calc-key" onClick={() => inputDigit('9')}>
            9
          </button>
          <button
            type="button"
            className="calc-key calc-key--accent"
            onClick={() => inputOp('-')}
          >
            −
          </button>

          <button type="button" className="calc-key" onClick={() => inputDigit('4')}>
            4
          </button>
          <button type="button" className="calc-key" onClick={() => inputDigit('5')}>
            5
          </button>
          <button type="button" className="calc-key" onClick={() => inputDigit('6')}>
            6
          </button>
          <button
            type="button"
            className="calc-key calc-key--accent"
            onClick={() => inputOp('+')}
          >
            +
          </button>

          <button type="button" className="calc-key" onClick={() => inputDigit('1')}>
            1
          </button>
          <button type="button" className="calc-key" onClick={() => inputDigit('2')}>
            2
          </button>
          <button type="button" className="calc-key" onClick={() => inputDigit('3')}>
            3
          </button>
          <button
            type="button"
            className="calc-key calc-key--accent"
            onClick={equals}
          >
            =
          </button>

          <button
            type="button"
            className="calc-key calc-key--wide"
            onClick={() => inputDigit('0')}
          >
            0
          </button>
          <button type="button" className="calc-key" onClick={() => inputDigit('.')}>
            .
          </button>
        </div>
      </div>
    </section>
  )
}
