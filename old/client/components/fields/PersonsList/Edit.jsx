import React from 'react'

import { shape, number, func, string, oneOfType, arrayOf, bool } from 'prop-types'
import { Button, Table, Form, Search, Popup, Message } from 'semantic-ui-react'
import debounce from 'lodash/debounce'

import { DateTimeField } from '/components/fields'
import { personTypes, personSex } from '/helpers/enums'
import { internalRequest } from '/helpers/request'
import getUid from '/helpers/getUid'
import config from '/helpers/config'

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
      middleName: string,
      birthDate: string,
      sex: oneOfType([string, number]).isRequired,
      role: oneOfType([string, number]).isRequired,
      countryId: oneOfType([string, number]).isRequired,
      phoneNumber: oneOfType([string, number]).isRequired,
      phoneNumber1: oneOfType([string, number]),
      address: oneOfType([string, number]),
      personSelected: bool,
    }),
    newRowId: number,
    onSave: func.isRequired,
    onCancel: func.isRequired,
    localize: func.isRequired,
    locale: string,
    countries: arrayOf(shape({})),
    disabled: bool,
    roles: arrayOf(shape({})),
  }

  static defaultProps = {
    data: {
      id: -1,
      givenName: '',
      personalId: '',
      surname: '',
      middleName: '',
      birthDate: null,
      sex: '',
      role: '',
      countryId: '',
      phoneNumber: '',
      phoneNumber1: '',
      address: '',
      personSelected: false,
    },
    newRowId: -1,
    countries: [],
    disabled: false,
    locale: '',
    roles: [],
  }

  state = {
    data: {
      ...this.props.data,
      id: this.props.newRowId,
    },
    isLoading: false,
    touched: false,
  }

  onFieldChange = (_, { name, value }) => {
    this.setState(s => ({
      data: { ...s.data, [name]: value },
      touched: true,
    }))
  }

  onSearchTextChange = (e, { value }) => {
    this.setState({ controlValue: value, isLoading: true }, () => this.searchData(value))
  }

  searchData = debounce((value) => {
    if (value.length > 0) {
      internalRequest({
        url: '/api/persons/search',
        method: 'get',
        queryParams: { wildcard: value },
        onSuccess: (resp) => {
          this.setState(() => ({
            results: resp.map(r => ({
              title: `${r.givenName} ${r.middleName === null ? '' : r.middleName} ${
                r.surname === null ? '' : r.surname
              }`,
              id: r.id,
              givenName: r.givenName,
              personalId: r.personalId,
              surname: r.surname,
              middleName: r.middleName,
              birthDate: r.birthDate,
              sex: r.sex,
              role: r.role,
              countryId: r.countryId,
              phoneNumber: r.phoneNumber,
              phoneNumber1: r.phoneNumber1,
              address: r.address,
              key: getUid(),
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
      })
    } else {
      this.setState({ isLoading: false })
    }
  }, 250)

  personSelectHandler = (e, { result }) => {
    this.setState(s => ({
      data: {
        ...s.data,
        id: result.id,
        givenName: result.givenName,
        personalId: result.personalId,
        surname: result.surname,
        middleName: result.middleName,
        birthDate: result.birthDate,
        sex: result.sex,
        countryId: result.countryId,
        phoneNumber: result.phoneNumber,
        phoneNumber1: result.phoneNumber1,
        address: result.address,
        personSelected: true,
      },
      touched: true,
    }))
  }

  saveHandler = () => {
    this.props.onSave(this.state.data, this.props.newRowId)
  }

  render() {
    const { localize, disabled, countries, roles } = this.props
    const { data, isLoading, results, controlValue, touched } = this.state
    const asOption = ([k, v]) => ({ value: k, text: localize(v) })
    const personMandatoryFields = config.mandatoryFields.Person
    const isMandatoryFieldEmpty =
      (personMandatoryFields.GivenName && !data.givenName) ||
      (personMandatoryFields.Surname && !data.surname) ||
      (personMandatoryFields.PersonalId && !data.personalId) ||
      (personMandatoryFields.MiddleName && !data.middleName) ||
      (personMandatoryFields.BirthDate && !data.birthDate) ||
      (personMandatoryFields.Role && !data.role) ||
      (personMandatoryFields.CountryId && !data.countryId) ||
      (personMandatoryFields.PhoneNumber && !data.phoneNumber) ||
      (personMandatoryFields.PhoneNumber1 && !data.phoneNumber1) ||
      (personMandatoryFields.Address && !data.address) ||
      (personMandatoryFields.Sex && !data.sex)

    return (
      <Table.Row>
        <Table.Cell colSpan={8}>
          <Form as="div">
            <Form.Group widths="equal">
              <div
                className="field"
                data-tooltip={localize('PersonTypeTooltip')}
                data-position="top left"
              >
                <Form.Select
                  label={localize('PersonType')}
                  placeholder={localize('PersonType')}
                  options={roles}
                  value={data.role}
                  name="role"
                  required={personMandatoryFields.Role}
                  onChange={this.onFieldChange}
                  disabled={disabled}
                />
              </div>
              <Popup
                trigger={
                  <Form.Field
                    label={localize('PersonsSearch')}
                    control={Search}
                    loading={isLoading}
                    placeholder={localize('PersonsSearch')}
                    onResultSelect={this.personSelectHandler}
                    onSearchChange={this.onSearchTextChange}
                    results={results}
                    value={controlValue}
                    showNoResults={false}
                    disabled={disabled}
                    fluid
                  />
                }
                content={localize('PersonSearchPopup')}
                position="top left"
              />
            </Form.Group>
            <Form.Group widths="equal">
              <div
                className="field"
                data-tooltip={localize('StatUnitFormPersonNameTooltip')}
                data-position="top left"
              >
                <Form.Input
                  label={localize('StatUnitFormPersonName')}
                  name="givenName"
                  value={data.givenName}
                  onChange={this.onFieldChange}
                  disabled={disabled}
                  readOnly={data.personSelected}
                  required={personMandatoryFields.GivenName}
                  autoComplete="off"
                />
              </div>
              <div
                className="field"
                data-tooltip={localize('SurnameTooltip')}
                data-position="top left"
              >
                <Form.Input
                  label={localize('Surname')}
                  name="surname"
                  value={data.surname}
                  onChange={this.onFieldChange}
                  disabled={disabled}
                  readOnly={data.personSelected}
                  required={personMandatoryFields.Surname}
                  autoComplete="off"
                />
              </div>
            </Form.Group>
            <Form.Group widths="equal">
              <div
                className="field"
                data-tooltip={localize('PersonalIdTooltip')}
                data-position="top left"
              >
                <Form.Input
                  label={localize('PersonalId')}
                  name="personalId"
                  value={data.personalId}
                  onChange={this.onFieldChange}
                  disabled={disabled || data.personSelected}
                  required={personMandatoryFields.PersonalId}
                  autoComplete="off"
                />
              </div>
              <div
                className="field"
                data-tooltip={localize('MiddleNameTooltip')}
                data-position="top left"
              >
                <Form.Input
                  label={localize('MiddleName')}
                  name="middleName"
                  value={data.middleName}
                  onChange={this.onFieldChange}
                  disabled={disabled || data.personSelected}
                  required={personMandatoryFields.MiddleName}
                  autoComplete="off"
                />
              </div>
            </Form.Group>
            <Form.Group widths="equal">
              <div
                className="field"
                data-tooltip={localize('BirthDateTooltip')}
                data-position="top left"
              >
                <DateTimeField
                  label="BirthDate"
                  name="birthDate"
                  value={data.birthDate}
                  onChange={this.onFieldChange}
                  disabled={disabled || data.personSelected}
                  localize={localize}
                  required={personMandatoryFields.BirthDate}
                />
              </div>
              <div className="field" data-tooltip={localize('SexTooltip')} data-position="top left">
                <Form.Select
                  name="sex"
                  label={localize('Sex')}
                  placeholder={localize('Sex')}
                  value={data.sex}
                  onChange={this.onFieldChange}
                  options={options.sex.map(asOption)}
                  disabled={disabled || data.personSelected}
                  required={personMandatoryFields.Sex}
                />
              </div>
            </Form.Group>
            <Form.Group widths="equal">
              <div
                className="field"
                data-tooltip={localize('CountryIdTooltip')}
                data-position="top left"
              >
                <Form.Select
                  label={localize('CountryId')}
                  placeholder={localize('CountryId')}
                  options={countries}
                  value={data.countryId}
                  name="countryId"
                  key="countryId"
                  required={personMandatoryFields.CountryId}
                  search
                  onChange={this.onFieldChange}
                  disabled={disabled || data.personSelected}
                />
              </div>
            </Form.Group>
            <Form.Group widths="equal">
              <div
                className="field"
                data-tooltip={localize('PhoneNumberTooltip')}
                data-position="top left"
              >
                <Form.Input
                  label={localize('PhoneNumber')}
                  name="phoneNumber"
                  value={data.phoneNumber}
                  onChange={this.onFieldChange}
                  disabled={disabled || data.personSelected}
                  required={personMandatoryFields.PhoneNumber}
                  autoComplete="off"
                />
              </div>
              <div
                className="field"
                data-tooltip={localize('PhoneNumber1Tooltip')}
                data-position="top left"
              >
                <Form.Input
                  label={localize('PhoneNumber1')}
                  name="phoneNumber1"
                  value={data.phoneNumber1}
                  onChange={this.onFieldChange}
                  disabled={disabled || data.personSelected}
                  required={personMandatoryFields.PhoneNumber1}
                  autoComplete="off"
                />
              </div>
            </Form.Group>
            <Form.Group widths="equal">
              <div
                className="field"
                data-tooltip={localize('AddressTooltip')}
                data-position="top left"
              >
                <Form.Input
                  label={localize('Address')}
                  name="address"
                  value={data.address}
                  onChange={this.onFieldChange}
                  disabled={disabled || data.personSelected}
                  required={personMandatoryFields.Address}
                  autoComplete="off"
                />
              </div>
            </Form.Group>

            <div>
              {isMandatoryFieldEmpty && (
                <Message content={localize('FixErrorsBeforeSubmit')} error />
              )}
            </div>

            <Form.Group widths="equal">
              <div className="field right aligned">
                <label htmlFor="saveBtn">&nbsp;</label>
                <Button.Group>
                  <div data-tooltip={localize('ButtonSave')} data-position="top center">
                    <Button
                      id="saveBtn"
                      icon="check"
                      color="green"
                      onClick={this.saveHandler}
                      disabled={disabled || isMandatoryFieldEmpty || !touched}
                    />
                  </div>
                  <div data-tooltip={localize('ButtonCancel')} data-position="top center">
                    <Button
                      icon="cancel"
                      color="red"
                      onClick={this.props.onCancel}
                      disabled={disabled}
                    />
                  </div>
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
