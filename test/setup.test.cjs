// First setup (scripts/setup.cjs): a bad plan is refused whole with every problem listed, a good one writes
// accounts, balances and budgets that read back the same, and running it twice changes nothing.
const { test } = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ledger-setup-test-'))
process.env.FINANCE_DB = path.join(dir, 'finance.sqlite')
const db = require('../server/db.cjs')
db.initDb(process.env.FINANCE_DB)
const setup = require('../scripts/setup.cjs')

test('a bad plan lists every problem and writes nothing', () => {
  const problems = setup.check({
    accounts: [{ name: 'Checking', kind: 'savings' }, { name: 'checking', kind: 'checking', currency: 'usd' },
      { name: '', kind: 'cash' }, { name: 'Card', kind: 'credit', balance: '12', as_of: '2999-01-01' }],
    budgets: [{ category: 'Food', limit: 0 }, { category: 'Fun', limit: 5, period: 'yearly' }],
  })
  assert.equal(problems.length, 8, problems.join('\n'))
  assert.equal(db.listAccounts().length, 0)
  assert.deepEqual(setup.check(null), ['the plan must be a JSON object'])
})

test('the example plan applies, reads back, and applies again without duplicates', () => {
  assert.deepEqual(setup.check(setup.EXAMPLE), [])
  setup.apply(setup.EXAMPLE)
  setup.apply(setup.EXAMPLE)
  const shown = setup.show()
  assert.deepEqual(shown.accounts.map((a) => [a.name, a.kind, a.balance]).sort(),
    [['Cash', 'cash', 60], ['Checking', 'checking', 2450.1], ['Friends', 'people', 0], ['Visa 1234', 'credit', 312.4]])
  assert.equal(shown.budgets.length, 3)
  assert.equal(shown.budgets.find((b) => b.category === 'Total').limit, 2500)
  assert.equal(db.listBalances('Checking').length, 1, 'same-day balance replaces itself')
  assert.match(setup.check({ accounts: [{ name: 'Cash', kind: 'cash', currency: 'INR' }] })[0], /already exists in USD/)
})
