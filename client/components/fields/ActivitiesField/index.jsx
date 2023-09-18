import React, { useState } from 'react'
import { shape, arrayOf, func, string, bool } from 'prop-types'
import { Icon, Table, Message } from 'semantic-ui-react'
import * as R from 'ramda'

import { getDate, formatDate } from '/client/helpers/dateHelper'
import ActivityView from './View'
import ActivityEdit from './Edit'

export function ActivitiesList(props) {
  const { localize, locale, name, value, onChange, label, readOnly, errors, disabled } = props

  const [addRow, setAddRow] = useState(false)
  const [editRow, setEditRow] = useState(undefined)
  const [newRowId, setNewRowId] = useState(-1)

  const editHandler = (index) => {
    setEditRow(index)
  }

  const deleteHandler = (index) => {
    changeHandler(value.filter((v, itemIndex) => itemIndex !== index))
  }

  const saveHandler = (editedValue, itemIndex) => {
    changeHandler(value.map((v, index) => (index === itemIndex ? editedValue : v)))
    setEditRow(undefined)
  }

  const editCancelHandler = () => {
    setEditRow(undefined)
  }

  const addHandler = () => {
    setAddRow(true)
  }

  const addSaveHandler = (newValue) => {
    changeHandler([newValue, ...value])
    setAddRow(false)
    setNewRowId(prevId => prevId - 1)
  }

  const addCancelHandler = () => {
    setAddRow(false)
  }

  const changeHandler = (newValue) => {
    const { name: inputName, onChange: onInputChange } = props
    onInputChange({ target: { name: inputName, value: newValue } }, { ...props, value: newValue })
  }

  const renderRows = () => {
    const renderComponent = (x, index) =>
      index !== editRow ? (
        <ActivityView
          key={index}
          value={x}
          onEdit={editHandler}
          onDelete={deleteHandler}
          readOnly={readOnly}
          editMode={editRow !== undefined || addRow}
          localize={localize}
          index={index}
        />
      ) : (
        <ActivityEdit
          key={index}
          value={x}
          onSave={saveHandler}
          onCancel={editCancelHandler}
          localize={localize}
          disabled={disabled}
          index={index}
        />
      )
    return value
      .sort((a, b) => a.activityType - b.activityType)
      .map((el, index) => renderComponent(el, index))
  }

  const labelContent = readOnly ? (
    <label className={props.required ? 'is-required' : ''}>{localize(label)}</label>
  ) : (
    <label className={props.required ? 'is-required' : ''} htmlFor={name}>
      {localize(label)}
    </label>
  )

  return (
    <div className="field">
      {labelContent}
      <Table size="small" id={name} compact celled>
        <Table.Header>
          <Table.Row>
            <Table.HeaderCell width={1} content={localize('StatUnitActivityRevXShort')} />
            <Table.HeaderCell width={5 + readOnly} content={localize('Activity')} />
            <Table.HeaderCell
              width={2}
              textAlign="center"
              content={localize('StatUnitActivityType')}
            />
            <Table.HeaderCell
              width={2}
              textAlign="center"
              content={localize('StatUnitActivityEmployeesNumber')}
            />
            <Table.HeaderCell width={2} textAlign="center" content={localize('Turnover')} />
            <Table.HeaderCell width={1} textAlign="center" content={localize('Year')} />
            {!readOnly && (
              <Table.HeaderCell width={1} textAlign="right">
                {editRow === undefined && addRow === false && (
                  <div data-tooltip={localize('ButtonAdd')} data-position="top center">
                    <Icon
                      name="add"
                      onClick={disabled ? R.identity : addHandler}
                      disabled={disabled}
                      color="green"
                      size="big"
                    />
                  </div>
                )}
              </Table.HeaderCell>
            )}
          </Table.Row>
        </Table.Header>
        <Table.Body>
          {addRow && (
            <ActivityEdit
              value={{
                id: newRowId,
                activityYear: 0,
                activityType: 1,
                employees: '',
                turnover: '',
                idDate: formatDate(getDate()),
                activityCategoryId: undefined,
              }}
              onSave={addSaveHandler}
              onCancel={addCancelHandler}
              localize={localize}
              disabled={disabled}
              locale={locale}
            />
          )}
          {value.length === 0 && !addRow ? (
            <Table.Row>
              <Table.Cell textAlign="center" colSpan="7" content={localize('TableNoRecords')} />
            </Table.Row>
          ) : (
            renderRows()
          )}
        </Table.Body>
      </Table>
      {errors.length !== 0 && <Message error title={localize(label)} list={errors.map(localize)} />}
    </div>
  )
}

ActivitiesList.propTypes = {
  localize: func.isRequired,
  locale: string.isRequired,
  name: string.isRequired,
  value: arrayOf(shape({})),
  onChange: func,
  label: string,
  readOnly: bool,
  errors: arrayOf(string),
  disabled: bool,
}

ActivitiesList.defaultProps = {
  value: [],
  readOnly: false,
  onChange: R.identity,
  label: '',
  errors: [],
  disabled: false,
}

export default ActivitiesList
