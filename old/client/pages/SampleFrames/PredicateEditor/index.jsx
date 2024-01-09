import React from 'react'
import PropTypes from 'prop-types'
import { Table } from 'semantic-ui-react'

import { predicate as predicatePropTypes } from '../propTypes.js'
import * as fns from '../predicateFns.js'
import Header from './Header.jsx'
import ClauseRow from './ClauseRow.jsx'

const PredicateEditor = ({ value: predicate, onChange, localize, locale, isEdit }) => {
  const { clauses, maxShift } = fns.flatten(predicate)
  const selected = fns.getSequentiallySelected(clauses)
  const anySelected = clauses.some(x => x.clause.selected)
  const group = () =>
    onChange(fns.group(
      predicate,
      selected.map(x => x.path),
    ))
  const toggleAll = () => onChange(fns.toggleAll(!anySelected)(predicate))
  const edit = path => (_, data) => onChange(fns.edit(path, data)(predicate))
  const add = (path, at) => () => onChange(fns.add(path, at)(predicate))
  const toggle = path => () => onChange(fns.toggle(path)(predicate))
  const toggleGroup = (path, value) => () => onChange(fns.toggleGroup(predicate, path, value))
  const ungroup = path => () => onChange(fns.ungroup(predicate, path))
  const remove = path => () => onChange(fns.remove(path)(predicate))
  const firstClausePath = clauses.length > 0 ? clauses[0].path : undefined
  const addHeadClause = () => onChange(fns.addHeadClause(predicate, firstClausePath))
  return (
    <Table basic="very" compact="very" size="small">
      <Header
        maxShift={maxShift}
        canGroup={selected.length > 1}
        anySelected={anySelected}
        group={group}
        toggleAll={toggleAll}
        onInsert={addHeadClause}
        localize={localize}
      />
      <Table.Body>
        {clauses.map(({ clause, path, meta }, i) => (
          <ClauseRow
            key={clause.uid}
            isEdit={isEdit}
            value={clause}
            path={path}
            meta={meta}
            isHead={i === 0}
            maxShift={maxShift}
            onChange={edit}
            onInsert={add}
            onToggle={toggle}
            onToggleGroup={toggleGroup}
            onUngroup={ungroup}
            onRemove={remove}
            localize={localize}
            locale={locale}
          />
        ))}
      </Table.Body>
    </Table>
  )
}

const { func, string } = PropTypes
PredicateEditor.propTypes = {
  value: predicatePropTypes.isRequired,
  onChange: func.isRequired,
  localize: func.isRequired,
  locale: string.isRequired,
}

export default PredicateEditor
