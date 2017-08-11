import React from 'react'
import { shape, arrayOf, func, string, bool } from 'prop-types'
import { Icon, Table, Popup, Message } from 'semantic-ui-react'

import { internalRequest } from 'helpers/request'
import PersonView from './View'
import PersonEdit from './Edit'

class PersonsList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    name: string.isRequired,
    value: arrayOf(shape({})),
    onChange: func,
    labelKey: string,
    readOnly: bool,
    errors: arrayOf(string).isRequired,
  }

  static defaultProps = {
    value: [],
    readOnly: false,
    onChange: v => v,
    labelKey: '',
  }

  state = {
    addRow: false,
    editRow: undefined,
    newRowId: -1,
    countries: [],
  }

  componentDidMount() {
    internalRequest({
      url: '/api/lookup/4',
      method: 'get',
      onSuccess: (countries) => { this.setState({ countries }) },
    })
  }

  editHandler = (editRow) => {
    this.setState({ editRow })
  }

  deleteHandler = (id) => {
    this.changeHandler(this.props.value.filter(v => v.id !== id))
  }

  saveHandler = (value) => {
    this.changeHandler(this.props.value.map(v => v.id === value.id ? value : v))
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

  isAlreadyExist = value => this.props.value.some(v =>
        v.givenName === value.givenName
        && v.personalId === value.personalId
        && v.surname === value.surname
        && v.birthDate === value.birthDate
        && v.sex === value.sex
        && v.role === value.role
        && v.countryId === value.countryId
        && v.phoneNumber === value.phoneNumber
        && v.phoneNumber1 === value.phoneNumber1
        && v.address === value.address)

  addCancelHandler = () => {
    this.setState({ addRow: false })
  }

  changeHandler(value) {
    const { onChange, name } = this.props
    onChange({ name, value })
  }

  renderRows() {
    const { readOnly, value, localize } = this.props
    const { addRow, editRow } = this.state
    const countriesLookup = this.state.countries.map(x => ({ value: x.id, text: x.name }))
    return value.map(v => (
      v.id !== editRow
        ? <PersonView
          key={v.id}
          data={v}
          onEdit={this.editHandler}
          onDelete={this.deleteHandler}
          readOnly={readOnly}
          editMode={editRow !== undefined || addRow}
          localize={localize}
          countries={countriesLookup}
        />
        : <PersonEdit
          key={v.id}
          data={v}
          onSave={this.saveHandler}
          onCancel={this.editCancelHandler}
          isAlreadyExist={this.isAlreadyExist}
          localize={localize}
          countries={countriesLookup}
          newRowId={v.id}
        />
    ))
  }

  render() {
    const { readOnly, value, labelKey, localize, errors, name } = this.props
    const { addRow, editRow, newRowId, countries } = this.state
    const label = localize(labelKey)
    return (
      <div className="field">
        {!readOnly && <label htmlFor={name}>{label}</label>}
        <Table size="small" id={name} compact celled>
          <Table.Header>
            <Table.Row>
              <Table.HeaderCell width={5}>{localize('PersonName')}</Table.HeaderCell>
              <Table.HeaderCell width={2}>{localize('PersonalId')}</Table.HeaderCell>
              <Table.HeaderCell width={2} textAlign="center">{localize('PersonType')}</Table.HeaderCell>
              <Table.HeaderCell width={1} textAlign="center">{localize('CountryId')}</Table.HeaderCell>
              <Table.HeaderCell width={2} textAlign="center">{localize('PhoneNumber')}</Table.HeaderCell>
              <Table.HeaderCell width={5} textAlign="center">{localize('Address')}</Table.HeaderCell>
              {!readOnly &&
                <Table.HeaderCell width={1} textAlign="right">
                  {editRow === undefined && addRow === false &&
                    <Popup
                      trigger={<Icon name="add" color="green" onClick={this.addHandler} />}
                      content={localize('ButtonAdd')}
                      size="mini"
                    />
                  }
                </Table.HeaderCell>
              }
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {addRow &&
              <PersonEdit
                key={newRowId}
                onSave={this.addSaveHandler}
                onCancel={this.addCancelHandler}
                isAlreadyExist={this.isAlreadyExist}
                localize={localize}
                newRowId={newRowId}
                countries={countries.map(x => ({ value: x.id, text: x.name }))}
              />
            }
            {value.length === 0 && !addRow
              ? (
                <Table.Row>
                  <Table.Cell textAlign="center" colSpan="7">
                    {localize('TableNoRecords')}
                  </Table.Cell>
                </Table.Row>
              )
              : this.renderRows()
            }
          </Table.Body>
        </Table>
        {errors.length !== 0 && <Message error title={label} list={errors.map(localize)} />}
      </div>
    )
  }
}

export default PersonsList
