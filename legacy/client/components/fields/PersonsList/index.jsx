import React from 'react'
import { shape, arrayOf, func, string, bool, number } from 'prop-types'
import { Icon, Table, Message } from 'semantic-ui-react'
import * as R from 'ramda'

import { internalRequest } from '/helpers/request'
import { hasValue } from '/helpers/validation'
import PersonView from './View.jsx'
import PersonEdit from './Edit.jsx'
import { getNewName } from '/helpers/locale'

export class PersonsList extends React.Component {
  static propTypes = {
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

  static defaultProps = {
    value: [],
    readOnly: false,
    onChange: R.identity,
    label: '',
    errors: [],
    disabled: false,
    required: false,
    regId: null,
  }

  state = {
    countries: [],
    addRow: false,
    editRow: undefined,
    newRowId: -1,
    roles: [],
  }

  componentDidMount() {
    internalRequest({
      url: '/api/lookup/4',
      method: 'get',
      onSuccess: (data) => {
        this.setState({
          countries: data.map(x => ({
            value: x.id,
            text: getNewName(x, false),
            ...x,
          })),
        })
      },
    })

    internalRequest({
      url: '/api/lookup/15',
      method: 'get',
      onSuccess: (data) => {
        this.setState({
          roles: data.map(x => ({
            value: x.id,
            text: getNewName(x, false),
            ...x,
          })),
        })
      },
    })
  }

  editHandler = (editRow) => {
    this.setState({ editRow })
  }

  deleteHandler = (id) => {
    this.changeHandler(this.props.value.filter(v => v.id !== id))
  }

  saveHandler = (value, id) => {
    this.changeHandler(this.props.value.map(v => (v.id === id ? value : v)))
    this.setState({ editRow: undefined })
  }

  editCancelHandler = () => {
    this.setState({ editRow: undefined })
  }

  addHandler = () => {
    this.setState({ addRow: true })
  }

  addSaveHandler = (value, id) => {
    this.changeHandler([value, ...this.props.value])
    this.setState(s => ({
      addRow: false,
      newRowId: s.newRowId - 1,
    }))
  }

  isAlreadyExist = value =>
    this.props.value.some(v =>
      v.id === value.id ||
        (v.givenName === value.givenName &&
          v.surname === value.surname &&
          v.middleName === value.middleName &&
          v.birthDate === value.birthDate &&
          v.sex === value.sex &&
          v.countryId === value.countryId &&
          v.phoneNumber === value.phoneNumber &&
          v.phoneNumber1 === value.phoneNumber1 &&
          v.address === value.address))

  addCancelHandler = () => {
    this.setState({ addRow: false })
  }

  changeHandler(value) {
    const { name, onChange } = this.props
    onChange({ target: { name, value } }, { ...this.props, value })
  }

  renderRows() {
    const { readOnly, value, localize, disabled, locale } = this.props
    const { countries, addRow, editRow, roles } = this.state

    const renderComponent = x =>
      x.id !== editRow ? (
        <PersonView
          key={`${x.role} - ${x.id}`}
          data={x}
          onEdit={this.editHandler}
          onDelete={this.deleteHandler}
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
          onSave={this.saveHandler}
          onCancel={this.editCancelHandler}
          isAlreadyExist={this.isAlreadyExist}
          localize={localize}
          locale={locale}
          countries={countries}
          newRowId={x.id}
          disabled={disabled}
          roles={roles}
        />
      )
    return value.map(renderComponent)
  }

  render() {
    const {
      readOnly,
      value,
      label: labelKey,
      localize,
      errors,
      name,
      disabled,
      required,
    } = this.props
    const { countries, addRow, editRow, newRowId, roles } = this.state
    const label = localize(labelKey)
    return (
      <div className="field">
        {!readOnly && (
          <label className={required ? 'is-required' : ''} htmlFor={name}>
            {label}
          </label>
        )}
        <Table size="small" id={name} compact celled>
          <Table.Header>
            <Table.Row>
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
                        onClick={disabled ? R.identity : this.addHandler}
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
                onSave={this.addSaveHandler}
                onCancel={this.addCancelHandler}
                isAlreadyExist={this.isAlreadyExist}
                localize={localize}
                newRowId={newRowId}
                countries={countries}
                disabled={disabled}
                roles={roles}
              />
            )}
            {value.length === 0 && !addRow ? (
              <Table.Row>
                <Table.Cell content={localize('TableNoRecords')} textAlign="center" colSpan="7" />
              </Table.Row>
            ) : (
              this.renderRows()
            )}
          </Table.Body>
        </Table>
        {errors.length !== 0 && <Message title={label} list={errors.map(localize)} error />}
      </div>
    )
  }
}

export default PersonsList
