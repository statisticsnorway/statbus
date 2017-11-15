import React from 'react'
import { shape, number, func, string, oneOfType, arrayOf, bool } from 'prop-types'
import { Button, Table, Form, Search, Popup } from 'semantic-ui-react'
import DatePicker from 'react-datepicker'
import debounce from 'lodash/debounce'

import { toUtc, dateFormat, getDate } from 'helpers/dateHelper'
import { internalRequest } from 'helpers/request'
import { personTypes, personSex } from 'helpers/enums'

const options = {
  sex: [...personSex],
  types: [...personTypes],
}

class PersonEdit extends React.Component {
  static propTypes = {
    data: shape({
      id: number,
      givenName: string.isRequired,
      personalId: oneOfType([string, number]),
      surname: string.isRequired,
      birthDate: string,
      sex: oneOfType([string, number]),
      role: oneOfType([string, number]).isRequired,
      countryId: oneOfType([string, number]).isRequired,
      phoneNumber: oneOfType([string, number]),
      phoneNumber1: oneOfType([string, number]),
      address: oneOfType([string, number]),
    }).isRequired,
    newRowId: number,
    onSave: func.isRequired,
    onCancel: func.isRequired,
    localize: func.isRequired,
    isAlreadyExist: func,
    countries: arrayOf(shape({})),
    disabled: bool,
  }

  static defaultProps = {
    data: {
      id: -1,
      givenName: '',
      personalId: '',
      surname: '',
      birthDate: null,
      sex: '',
      role: '',
      countryId: '',
      phoneNumber: '',
      phoneNumber1: '',
      address: '',
    },
    newRowId: -1,
    countries: [],
    isAlreadyExist: () => false,
    disabled: false,
  }

  state = {
    data: { ...this.props.data, id: this.props.newRowId },
    isLoading: false,
    isOpen: false,
    edited: false,
    isAlreadyExist: false,
  }

  onFieldChange = (_, { name, value }) => {
    this.setState(
      s => ({
        data: { ...s.data, [name]: value },
        edited: true,
        isAlreadyExist: this.props.isAlreadyExist({ ...s.data, [name]: value }),
      }),
      // this is for correctly Popup work see 2 first comments on this page
      // https://github.com/Semantic-Org/Semantic-UI-React/issues/1065
      document.getElementById('saveBtnDiv').click,
    )
  }

  onDateFieldChange = name => (date) => {
    this.setState(s => ({
      data: { ...s.data, [name]: date === null ? null : toUtc(date) },
      edited: true,
    }))
  }

  onPersonChange = (e, { value }) => {
    this.setState(
      s => ({ data: { ...s.data }, isLoading: true }),
      () => {
        this.searchData(value)
      },
    )
  }

  searchData = debounce(
    value =>
      internalRequest({
        url: '/api/persons/search',
        method: 'get',
        queryParams: { wildcard: value },
        onSuccess: (resp) => {
          this.setState(s => ({
            data: { ...s.data },
            controlValue: value,
            results: resp.map(r => ({
              title: `${r.givenName} ${r.surname}`,
              id: r.id,
              givenName: r.givenName,
              personalId: r.personalId,
              surname: r.surname,
              birthDate: r.birthDate,
              sex: r.sex,
              role: r.role,
              countryId: r.countryId,
              phoneNumber: r.phoneNumber,
              phoneNumber1: r.phoneNumber1,
              address: r.address,
              key: r.id,
            })),
            isLoading: false,
          }))
        },
        onFail: () => {
          this.setState({
            isLoading: false,
            controlValue: value,
          })
        },
      }),
    250,
  )

  personSelectHandler = (e, { result }) => {
    this.setState(
      s => ({
        data: {
          ...s.data,
          id: this.props.newRowId,
          givenName: result.givenName,
          personalId: result.personalId,
          surname: result.surname,
          birthDate: result.birthDate,
          sex: result.sex,
          role: result.role,
          countryId: result.countryId,
          phoneNumber: result.phoneNumber,
          phoneNumber1: result.phoneNumber1,
          address: result.address,
        },
        edited: true,
        isAlreadyExist: this.props.isAlreadyExist({
          ...s.data,
          id: this.props.newRowId,
          givenName: result.givenName,
          personalId: result.personalId,
          surname: result.surname,
          birthDate: result.birthDate,
          sex: result.sex,
          role: result.role,
          countryId: result.countryId,
          phoneNumber: result.phoneNumber,
          phoneNumber1: result.phoneNumber1,
          address: result.address,
        }),
      }),
      // this is for correctly Popup work see 2 first comments on this page
      // https://github.com/Semantic-Org/Semantic-UI-React/issues/1065
      document.getElementById('saveBtnDiv').click,
    )
  }

  saveHandler = () => {
    this.props.onSave(this.state.data)
  }

  handleOpen = () => {
    this.setState({ isOpen: true })
  }

  render() {
    const { localize, countries, disabled } = this.props
    const { data, isLoading, results, controlValue, edited, isAlreadyExist } = this.state
    const asOption = ([k, v]) => ({ value: k, text: localize(v) })
    return (
      <Table.Row>
        <Table.Cell colSpan={8}>
          <Form as="div">
            <Form.Group widths="equal">
              <Form.Field
                label={localize('PersonsSearch')}
                control={Search}
                loading={isLoading}
                placeholder={localize('PersonsSearch')}
                onResultSelect={this.personSelectHandler}
                onSearchChange={this.onPersonChange}
                results={results}
                value={controlValue}
                showNoResults={false}
                disabled={disabled}
                fluid
              />
              <Form.Input
                label={localize('StatUnitFormPersonName')}
                name="givenName"
                value={data.givenName}
                onChange={this.onFieldChange}
                disabled={disabled}
                required
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Input
                label={localize('Surname')}
                name="surname"
                value={data.surname}
                onChange={this.onFieldChange}
                disabled={disabled}
                required
              />
              <Form.Input
                label={localize('PersonalId')}
                name="personalId"
                value={data.personalId}
                onChange={this.onFieldChange}
                disabled={disabled}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <div className="field datepicker">
                <label htmlFor="birthDate">{localize('BirthDate')}</label>
                <DatePicker
                  id="birthDate"
                  value={data.birthDate}
                  onChange={this.onDateFieldChange('birthDate')}
                  selected={data.birthDate === null ? '' : getDate(data.birthDate)}
                  dateFormat={dateFormat}
                  className="ui input"
                  type="number"
                  name="birthDate"
                  disabled={disabled}
                />
              </div>
              <Form.Select
                name="sex"
                label={localize('Sex')}
                placeholder={localize('Sex')}
                value={data.sex}
                onChange={this.onFieldChange}
                options={options.sex.map(asOption)}
                disabled={disabled}
                required
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Select
                label={localize('PersonType')}
                placeholder={localize('PersonType')}
                options={options.types.map(asOption)}
                value={data.role}
                name="role"
                required
                onChange={this.onFieldChange}
                disabled={disabled}
              />
              <Form.Select
                label={localize('CountryId')}
                placeholder={localize('CountryId')}
                options={countries}
                value={data.countryId}
                name="countryId"
                key="countryId"
                required
                search
                onChange={this.onFieldChange}
                disabled={disabled}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Input
                label={localize('PhoneNumber')}
                name="phoneNumber"
                value={data.phoneNumber}
                onChange={this.onFieldChange}
                disabled={disabled}
                required
              />
              <Form.Input
                label={localize('PhoneNumber1')}
                name="phoneNumber1"
                value={data.phoneNumber1}
                onChange={this.onFieldChange}
                disabled={disabled}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Input
                label={localize('Address')}
                name="address"
                value={data.address}
                onChange={this.onFieldChange}
                disabled={disabled}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <div className="field right aligned">
                <label htmlFor="saveBtn">&nbsp;</label>
                <Button.Group>
                  <Popup
                    trigger={
                      <div id="saveBtnDiv">
                        <Button
                          id="saveBtn"
                          icon="check"
                          color="green"
                          onClick={this.saveHandler}
                          disabled={
                            disabled ||
                            !data.givenName ||
                            !data.surname ||
                            !data.countryId ||
                            !data.role ||
                            !edited ||
                            isAlreadyExist
                          }
                        />
                      </div>
                    }
                    content={localize('PersonAlreadyExists')}
                    open={this.state.isAlreadyExist}
                    onOpen={this.handleOpen}
                  />
                  <Button
                    icon="cancel"
                    color="red"
                    onClick={this.props.onCancel}
                    disabled={disabled}
                  />
                </Button.Group>
              </div>
            </Form.Group>
          </Form>
        </Table.Cell>
      </Table.Row>
    )
  }
}

export default PersonEdit
