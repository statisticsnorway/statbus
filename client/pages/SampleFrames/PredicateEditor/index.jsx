import React from 'react'
import PropTypes from 'prop-types'
import { Table, Icon } from 'semantic-ui-react'

import { predicate as predicatePropTypes } from '../propTypes'
import * as fns from '../predicateFns'
import ClauseRow from './ClauseRow'
import styles from './styles.pcss'

const { Header, Body, Row, HeaderCell } = Table

const PredicateEditor = ({ value: predicate, onChange, localize }) => {
  const { clauses, maxShift } = fns.flatten(predicate)
  const selected = fns.getSelected(clauses)
  const cantGroup = true // selected === null || selected.length <= 1
  const cantDeselect = clauses.every(x => !x.clause.selected)
  const group = cantGroup ? undefined : () => onChange(fns.group(predicate, selected))
  const toggleAll = () => onChange(fns.toggleAll(cantDeselect)(predicate))
  const edit = path => (_, data) => onChange(fns.edit(path, data)(predicate))
  const add = (path, at) => () => onChange(fns.add(path, at)(predicate))
  const toggle = path => () => onChange(fns.toggle(path)(predicate))
  const toggleGroup = (path, value) => () => onChange(fns.toggleGroup(predicate, path, value))
  const ungroup = path => () => onChange(fns.ungroup(predicate, path))
  const remove = path => () => onChange(fns.remove(path)(predicate))
  return (
    <Table basic="very" compact="very" size="small">
      <Header>
        <Row>
          <HeaderCell textAlign="right" colSpan={maxShift + 1} collapsing>
            <Icon.Group
              onClick={group}
              title={localize('GroupSelectedClauses')}
              className="cursor-pointer"
              size="large"
            >
              <Icon name="sitemap" disabled={cantGroup} className={styles['rotated-270']} />
              <Icon
                name="add"
                disabled={cantGroup}
                className={styles['large-corner-icon']}
                color="green"
                corner
              />
            </Icon.Group>
            &nbsp;
            <Icon.Group
              onClick={toggleAll}
              title={localize(cantDeselect ? 'DeselectAll' : 'SelectAll')}
              className="cursor-pointer"
              size="large"
            >
              <Icon name="checkmark box" color="grey" />
              <Icon
                name={cantDeselect ? 'checkmark box' : 'x'}
                className={styles['large-corner-icon']}
                color={cantDeselect ? 'blue' : 'red'}
                corner
              />
            </Icon.Group>
          </HeaderCell>
          {['Comparisons', 'Fields', 'Operations', 'Values'].map(x => (
            <HeaderCell key={x} content={localize(x)} textAlign="center" />
          ))}
          <HeaderCell textAlign="center" />
        </Row>
      </Header>
      <Body>
        {clauses.map(({ clause, path, meta }, i) => (
          <ClauseRow
            key={clause.uid}
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
          />
        ))}
      </Body>
    </Table>
  )
}

const { func } = PropTypes
PredicateEditor.propTypes = {
  value: predicatePropTypes.isRequired,
  onChange: func.isRequired,
  localize: func.isRequired,
}

export default PredicateEditor
