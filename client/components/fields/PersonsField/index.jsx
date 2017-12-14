import React from 'react'
import { shape, arrayOf, func, string, bool } from 'prop-types'
import { Icon, Table, Popup, Message } from 'semantic-ui-react'

import { internalRequest } from 'helpers/request'
import PersonView from './View'
import PersonEdit from './Edit'

const stubF = _ => _

class PersonsList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    name: string.isRequired,
    value: arrayOf(shape({})),
    setFieldValue: func,
    label: string,
    readOnly: bool,
    errors: arrayOf(string),
    disabled: bool,
  }

  static defaultProps = {
    value: [],
    readOnly: false,
    setFieldValue: v => v,
    label: '',
    errors: [],
    disabled: false,
  }

  state = {
    countries: [],
    addRow: false,
    editRow: undefined,
    newRowId: -1,
  }

  componentDidMount() {
    internalRequest({
      url: '/api/lookup/4',
      method: 'get',
      onSuccess: data =>
        this.setState({ countries: data.map(x => ({ value: x.id, text: x.name })) }),
    })
  }

  editHandler = (editRow) => {
    this.setState({ editRow })
  }

  deleteHandler = (id) => {
    this.changeHandler(this.props.value.filter(v => v.id !== id))
  }

  saveHandler = (value) => {
    this.changeHandler(this.props.value.map(v => (v.id === value.id ? value : v)))
    this.setState({ editRow: undefined })
  }

  editCancelHandler = () => {
    this.setState({ editRow: undefined })
  }

  addHandler = () => {
    this.setState({ addRow: true })
  }

  addSaveHandler = (value) => {
    this.changeHandler([value, ...this.props.value])
    this.setState(s => ({
      addRow: false,
      newRowId: s.newRowId - 1,
    }))
  }

  isAlreadyExist = value =>
    this.props.value.some(v =>
      v.givenName === value.givenName &&
        v.personalId === value.personalId &&
        v.surname === value.surname &&
        v.birthDate === value.birthDate &&
        v.sex === value.sex &&
        v.role === value.role &&
        v.countryId === value.countryId &&
        v.phoneNumber === value.phoneNumber &&
        v.phoneNumber1 === value.phoneNumber1 &&
        v.address === value.address)

  addCancelHandler = () => {
    this.setState({ addRow: false })
  }

  changeHandler(value) {
    this.props.setFieldValue(this.props.name, value)
  }

  renderRows() {
    const { readOnly, value, localize, disabled } = this.props
    const { countries, addRow, editRow } = this.state
    return value.map(v =>
      v.id !== editRow ? (
        <PersonView
          key={v.id}
          data={v}
          onEdit={this.editHandler}
          onDelete={this.deleteHandler}
          readOnly={readOnly}
          editMode={editRow !== undefined || addRow}
          localize={localize}
          countries={countries}
        />
      ) : (
        <PersonEdit
          key={v.id}
          data={v}
          onSave={this.saveHandler}
          onCancel={this.editCancelHandler}
          isAlreadyExist={this.isAlreadyExist}
          localize={localize}
          countries={countries}
          newRowId={v.id}
          disabled={disabled}
        />
      ))
  }

  render() {
    const { readOnly, value, label: labelKey, localize, errors, name, disabled } = this.props
    const { countries, addRow, editRow, newRowId } = this.state
    const label = localize(labelKey)
    return (
      <div className="field">
        {!readOnly && <label className="is-required" htmlFor={name}>{label}</label>}
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
                  {editRow === undefined &&
                    addRow === false && (
                      <Popup
                        trigger={
                          <Icon
                            name="add"
                            onClick={disabled ? stubF : this.addHandler}
                            disabled={disabled}
                            color="green"
                            size="big"
                          />
                        }
                        content={localize('ButtonAdd')}
                        size="mini"
                      />
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
