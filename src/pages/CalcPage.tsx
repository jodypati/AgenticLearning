import type { KeyboardEvent } from 'react'
import { useCallback, useEffect, useReducer, useRef } from 'react'
import './CalcPage.css'

type Op = '+' | '-' | '*' | '/'

type CalcState = {
  display: string
  acc: number | null
  op: Op | null
  newEntry: boolean
}

const initialState: CalcState = {
  display: '0',
  acc: null,
  op: null,
  newEntry: false,
}

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

type CalcAction =
  | { type: 'digit'; digit: string }
  | { type: 'op'; op: Op }
  | { type: 'equals' }
  | { type: 'clear' }
  | { type: 'back' }

function reducer(state: CalcState, action: CalcAction): CalcState {
  switch (action.type) {
    case 'clear':
      return initialState

    case 'digit': {
      const { digit } = action
      if (state.display === 'Error') {
        return {
          ...initialState,
          display: digit === '.' ? '0.' : digit,
          newEntry: false,
        }
      }
      if (state.newEntry) {
        return {
          ...state,
          newEntry: false,
          display: digit === '.' ? '0.' : digit,
        }
      }
      if (digit === '.' && state.display.includes('.')) {
        return state
      }
      if (state.display === '0' && digit !== '.') {
        return { ...state, display: digit }
      }
      return { ...state, display: state.display + digit }
    }

    case 'op': {
      const { op } = action
      if (state.display === 'Error') {
        return state
      }
      const current = parseFloat(state.display)

      if (state.acc !== null && state.op !== null && !state.newEntry) {
        const result = applyOp(state.acc, current, state.op)
        if (Number.isNaN(result)) {
          return {
            ...state,
            acc: null,
            op,
            display: 'Error',
            newEntry: true,
          }
        }
        return {
          ...state,
          acc: result,
          op,
          display: formatResult(result),
          newEntry: true,
        }
      }

      return {
        ...state,
        acc: current,
        op,
        newEntry: true,
      }
    }

    case 'equals': {
      if (state.op === null || state.acc === null || state.display === 'Error') {
        return state
      }
      const current = parseFloat(state.display)
      const result = applyOp(state.acc, current, state.op)
      if (Number.isNaN(result)) {
        return {
          ...initialState,
          display: 'Error',
          newEntry: true,
        }
      }
      return {
        ...initialState,
        display: formatResult(result),
        newEntry: true,
      }
    }

    case 'back': {
      if (state.newEntry || state.display === 'Error') {
        return state
      }
      if (state.display.length <= 1) {
        return { ...state, display: '0' }
      }
      const next = state.display.slice(0, -1)
      return {
        ...state,
        display: next === '' || next === '-' ? '0' : next,
      }
    }

    default:
      return state
  }
}

export default function CalcPage() {
  const [state, dispatch] = useReducer(reducer, initialState)
  const sectionRef = useRef<HTMLElement>(null)

  useEffect(() => {
    sectionRef.current?.focus({ preventScroll: true })
  }, [])

  const inputDigit = useCallback((digit: string) => {
    dispatch({ type: 'digit', digit })
  }, [])

  const inputOp = useCallback((op: Op) => {
    dispatch({ type: 'op', op })
  }, [])

  const equals = useCallback(() => {
    dispatch({ type: 'equals' })
  }, [])

  const resetAll = useCallback(() => {
    dispatch({ type: 'clear' })
  }, [])

  const backspace = useCallback(() => {
    dispatch({ type: 'back' })
  }, [])

  const onKeyDown = useCallback(
    (e: KeyboardEvent<HTMLElement>) => {
      const { key } = e
      if (/^[0-9]$/.test(key)) {
        e.preventDefault()
        dispatch({ type: 'digit', digit: key })
        return
      }
      if (key === '.') {
        e.preventDefault()
        dispatch({ type: 'digit', digit: '.' })
        return
      }
      if (key === 'Enter' || key === '=') {
        e.preventDefault()
        dispatch({ type: 'equals' })
        return
      }
      if (key === 'Escape') {
        e.preventDefault()
        dispatch({ type: 'clear' })
        return
      }
      if (key === 'Backspace') {
        e.preventDefault()
        dispatch({ type: 'back' })
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
        dispatch({ type: 'op', op: opMap[key]! })
      }
    },
    [],
  )

  const { display } = state

  return (
    <section
      ref={sectionRef}
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
