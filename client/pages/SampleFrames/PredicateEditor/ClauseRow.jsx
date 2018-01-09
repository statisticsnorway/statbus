/* eslint-disable no-mixed-operators */
import React from 'react'
import PropTypes from 'prop-types'
import { Dropdown, Table, Input, Icon } from 'semantic-ui-react'
import R from 'ramda'

import { clause as clausePropTypes } from '../propTypes'
import getOptions from './getOptions'
import styles from './styles.pcss'

const { Row, Cell } = Table
const ClauseRow = ({
  value: clause,
  path,
  meta: { shift, startAt, endAt, allSelectedAt },
  isHead,
  maxShift,
  onChange,
  onInsert,
  onToggle,
  onToggleGroup,
  onRemove,
  onUngroup,
  localize,
}) => {
  const options = getOptions(isHead, localize)
  const handleChange = onChange(path)
  const propsFor = name => ({
    name,
    value: clause[name],
    options: options[name],
    onChange: handleChange,
  })
  const lastGroupCellSpan = maxShift - shift + 1
  const toGroupCell = (i) => {
    const isTop = startAt.includes(i)
    const allSelected = allSelectedAt.includes(i)
    const cellClasses =
      `${styles.group} ${styles[`group-${(i - 1) % 10}`]} ${styles['group-edge']} ` +
      `${isTop ? styles['group-start'] : ''} ` +
      `${endAt.includes(i) ? styles['group-end'] : ''}`
    const colSpan = i === shift ? lastGroupCellSpan : 1
    const subPath = isTop ? path.slice(0, i) : undefined
    return (
      <Cell key={i} className={cellClasses} colSpan={colSpan} collapsing>
        {isTop && (
          <Icon
            onClick={onToggleGroup(subPath, !allSelected)}
            name={allSelected ? 'checkmark box' : 'square outline'}
            color={allSelected ? 'blue' : undefined}
            title={localize(allSelected ? 'UnselectClauseGroup' : 'SelectClauseGroup')}
            className="cursor-pointer"
          />
        )}
        {isTop && (
          <Icon.Group
            onClick={onUngroup(subPath)}
            title={localize('UngroupClauses')}
            className="cursor-pointer"
          >
            <Icon name="sitemap" className={styles['rotated-270']} />
            <Icon name="x" color="red" className={styles['large-corner-icon']} corner />
          </Icon.Group>
        )}
      </Cell>
    )
  }
  return (
    <Row active={clause.selected}>
      {R.range(1, shift + 1).map(toGroupCell)}
      <Cell colSpan={shift === 0 ? lastGroupCellSpan : 1} textAlign="right" collapsing>
        <Icon
          onClick={onToggle(path)}
          name={clause.selected ? 'checkmark box' : 'square outline'}
          color={clause.selected ? 'blue' : undefined}
          title={localize(clause.selected ? 'UnselectClause' : 'SelectClause')}
          size="large"
          className="cursor-pointer"
        />
        &nbsp;
      </Cell>
      {['comparison', 'field', 'operation'].map(x => (
        <Cell key={x} textAlign="center" collapsing>
          <Dropdown {...propsFor(x)} size="mini" search />
        </Cell>
      ))}
      <Cell>
        <Input {...R.omit(['options'], propsFor('value'))} size="mini" fluid />
      </Cell>
      <Cell textAlign="center" collapsing>
        <Icon
          onClick={isHead ? undefined : onRemove(path)}
          disabled={isHead}
          name="x"
          color="red"
          title={localize('Remove')}
          size="large"
          className="cursor-pointer"
        />
        <Icon.Group
          onClick={onInsert(R.take(path.length - 1, path), R.last(path) + 1)}
          className="cursor-pointer"
          title={localize('InsertAfter')}
          size="large"
        >
          <Icon name="add" color="blue" />
          <Icon name="external" className={styles.flipped} corner />
        </Icon.Group>
      </Cell>
    </Row>
  )
}

const { arrayOf, bool, func, number, oneOfType, shape, string } = PropTypes
ClauseRow.propTypes = {
  value: clausePropTypes.isRequired,
  path: arrayOf(oneOfType([number, string])).isRequired,
  meta: shape({
    shift: number.isRequired,
    startAt: arrayOf(number).isRequired,
    endAt: arrayOf(number).isRequired,
    allSelectedAt: arrayOf(number).isRequired,
  }).isRequired,
  isHead: bool.isRequired,
  maxShift: number.isRequired,
  onChange: func.isRequired,
  onInsert: func.isRequired,
  onToggle: func.isRequired,
  onToggleGroup: func.isRequired,
  onRemove: func.isRequired,
  onUngroup: func.isRequired,
  localize: func.isRequired,
}

export default ClauseRow
