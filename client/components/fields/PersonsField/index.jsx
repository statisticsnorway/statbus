import React, { useState, useEffect } from 'react'
import { shape, arrayOf, func, string, bool, number, target, value } from 'prop-types'
import { Icon, Table, Message } from 'semantic-ui-react'
import * as R from 'ramda'

import { internalRequest } from '/client/helpers/request'
import { hasValue } from '/client/helpers/validation'
import PersonView from './View'
import PersonEdit from './Edit'
import { getNewName } from '/client/helpers/locale'

export function PersonsList({
  localize,
  locale,
  name,
  value: initialData,
  onChange,
  label,
  readOnly,
  errors,
  disabled,
  required,
  regId,
}) {
  const [countries, setCountries] = useState([])
  const [addRow, setAddRow] = useState(false)
  const [editRow, setEditRow] = useState(undefined)
  const [newRowId, setNewRowId] = useState(-1)
  const [roles, setRoles] = useState([])

  useEffect(() => {
    internalRequest({
      url: '/api/lookup/4',
      method: 'get',
      onSuccess: (data) => {
        setCountries(data.map(x => ({
          value: x.id,
          text: getNewName(x, false),
          ...x,
        })))
      },
    })

    internalRequest({
      url: '/api/lookup/15',
      method: 'get',
      onSuccess: (data) => {
        setRoles(data.map(x => ({
          value: x.id,
          text: getNewName(x, false),
          ...x,
        })))
      },
    })
  }, [])

  const editHandler = (editRow) => {
    setEditRow(editRow)
  }

  const deleteHandler = (id) => {
    changeHandler(initialData.filter(v => v.id !== id))
  }

  const saveHandler = (value, id) => {
    changeHandler(initialData.map(v => (v.id === id ? value : v)))
    setEditRow(undefined)
  }

  const editCancelHandler = () => {
    setEditRow(undefined)
  }

  const addHandler = () => {
    setAddRow(true)
  }

  const addSaveHandler = (value, id) => {
    changeHandler([value, ...initialData])
    setAddRow(false)
    setNewRowId(prevId => prevId - 1)
  }

  const isAlreadyExist = value =>
    initialData.some(v =>
      v.id === value.id ||
        (v.givenName === value.givenName &&
          v.personalId === value.personalId &&
          v.surname === value.surname &&
          v.middleName === value.middleName &&
          v.birthDate === value.birthDate &&
          v.sex === value.sex &&
          v.countryId === value.countryId &&
          v.phoneNumber === value.phoneNumber &&
          v.phoneNumber1 === value.phoneNumber1 &&
          v.address === value.address))

  const changeHandler = (data) => {
    onChange({ target: { name, value: data } }, { ...value, value: data })
  }

  const renderRows = () => initialData.map(x =>
    x.id !== editRow ? (
      <PersonView
        key={`${x.role} - ${x.id}`}
        data={x}
        onEdit={editHandler}
        onDelete={deleteHandler}
        readOnly={readOnly}
        editMode={editRow !== undefined || addRow}
        localize={localize}
        countries={countries}
        roles={roles}
      />
    ) : (
      <PersonEdit
        key={`${x.role} - ${x.id}`}
        data={x}
        onSave={saveHandler}
        onCancel={editCancelHandler}
        isAlreadyExist={isAlreadyExist}
        localize={localize}
        locale={locale}
        countries={countries}
        newRowId={x.id}
        disabled={disabled}
        roles={roles}
      />
    ))

  const labelContent = (
    <label className={required ? 'is-required' : ''} htmlFor={name}>
      {localize(label)}
    </label>
  )

  return (
    <div className="field">
      {!readOnly && labelContent}
      <Table size="small" id={name} compact celled>
        <Table.Header>
          <Table.Row>
            <Table.HeaderCell content={localize('PersonalId')} width={2} textAlign="center" />
            <Table.HeaderCell content={localize('PersonName')} width={3} textAlign="center" />
            <Table.HeaderCell content={localize('Sex')} width={1} textAlign="center" />
            <Table.HeaderCell content={localize('CountryId')} width={2} textAlign="center" />
            <Table.HeaderCell content={localize('PersonType')} width={2} textAlign="center" />
            <Table.HeaderCell content={localize('PhoneNumber')} width={2} textAlign="center" />
            <Table.HeaderCell content={localize('PhoneNumber1')} width={2} textAlign="center" />
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
            <PersonEdit
              key={newRowId}
              onSave={addSaveHandler}
              onCancel={() => setAddRow(false)}
              isAlreadyExist={isAlreadyExist}
              localize={localize}
              newRowId={newRowId}
              countries={countries}
              disabled={disabled}
              roles={roles}
            />
          )}
          {initialData.length === 0 && !addRow ? (
            <Table.Row>
              <Table.Cell content={localize('TableNoRecords')} textAlign="center" colSpan="7" />
            </Table.Row>
          ) : (
            renderRows()
          )}
        </Table.Body>
      </Table>
      {errors.length !== 0 && <Message title={localize(label)} list={errors.map(localize)} error />}
    </div>
  )
}

PersonsList.propTypes = {
  localize: func.isRequired,
  locale: string.isRequired,
  name: string.isRequired,
  value: arrayOf(shape({})),
  onChange: func,
  label: string,
  readOnly: bool,
  errors: arrayOf(string),
  disabled: bool,
  required: bool,
  regId: number,
}

PersonsList.defaultProps = {
  value: [],
  readOnly: false,
  onChange: R.identity,
  label: '',
  errors: [],
  disabled: false,
  required: false,
  regId: null,
}

