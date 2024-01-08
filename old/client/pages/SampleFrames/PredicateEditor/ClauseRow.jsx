/* eslint-disable no-mixed-operators */
import React from 'react'
import PropTypes from 'prop-types'
import { Dropdown, Table, Input, Icon } from 'semantic-ui-react'
import * as R from 'ramda'

import { predicateFields } from '/helpers/config'
import { pairsToOptions } from '/helpers/enumerable'
import { predicateComparison, predicateOperations } from '/helpers/enums'
import { clause as clausePropTypes } from '../propTypes.js'
import InsertButton from './InsertButton.jsx'
import ValueInput from './ValueInput.jsx'
import styles from './styles.scss'

const getCellClassName = (isStart, isEnd, i) =>
  `${styles.group} ${styles[`group-${(i - 1) % 10}`]} ${styles['group-edge']} ` +
  `${isStart ? styles['group-start'] : ''} ` +
  `${isEnd ? styles['group-end'] : ''}`

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
  locale,
  isEdit,
}) => {
  const handleChange = onChange(path)
  const propsFor = name => ({
    name,
    value: clause[name],
    onChange: handleChange,
  })
  const lastGroupCellSpan = maxShift - shift + 1
  const toGroupCell = (i) => {
    const isTop = startAt.includes(i)
    const className = getCellClassName(isTop, endAt.includes(i), i)
    const allSelected = allSelectedAt.includes(i)
    const colSpan = i === shift ? lastGroupCellSpan : 1
    return (
      <Cell key={i} className={className} colSpan={colSpan} collapsing>
        {isTop && (
          <Icon
            onClick={onToggleGroup(path, !allSelected)}
            name={allSelected ? 'checkmark box' : 'square outline'}
            color={allSelected ? 'blue' : undefined}
            title={localize(allSelected ? 'UnselectClauseGroup' : 'SelectClauseGroup')}
            className="cursor-pointer"
          />
        )}
        {isTop && (
          <Icon.Group
            onClick={onUngroup(path)}
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
  const allOperations = pairsToOptions(predicateOperations, localize)
  const operationsFor = field =>
    allOperations.filter(x => predicateFields.get(field).operations.includes(x.value))
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
      <Cell textAlign="center" collapsing>
        <Dropdown
          {...propsFor('comparison')}
          disabled={isHead}
          options={pairsToOptions(predicateComparison, localize)}
          size="mini"
          search
        />
      </Cell>
      <Cell textAlign="center" collapsing>
        <Dropdown
          {...propsFor('field')}
          options={pairsToOptions(predicateFields, x => localize(x.value))}
          size="mini"
          search
        />
      </Cell>
      <Cell textAlign="center" collapsing>
        <Dropdown
          {...propsFor('operation')}
          options={operationsFor(clause.field)}
          size="mini"
          search
        />
      </Cell>
      <Cell>
        <ValueInput
          field={clause.field}
          operation={clause.operation}
          localize={localize}
          locale={locale}
          isEdit={isEdit}
          {...propsFor('value')}
          size="mini"
          fluid
        />
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
        <InsertButton
          onClick={onInsert(R.take(path.length - 1, path), R.last(path) + 1)}
          title={localize('InsertAfter')}
        />
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
  locale: string.isRequired,
}

export default ClauseRow
