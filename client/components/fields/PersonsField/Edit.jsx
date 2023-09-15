import React, { useState, useEffect } from 'react'
import PropTypes from 'prop-types'
import { Button, Table, Form, Search, Popup, Message } from 'semantic-ui-react'
import debounce from 'lodash/debounce'

import { DateTimeField } from '/client/components/fields'
import { personTypes, personSex } from '/client/helpers/enums'
import { internalRequest } from '/client/helpers/request'
import getUid from '/client/helpers/getUid'
import config from '/client/helpers/config'

const options = {
  sex: [...personSex],
  types: [...personTypes],
}

function PersonEdit(props) {
  const { data, newRowId, onSave, onCancel, localize, locale, countries, roles, disabled } = props

  const [formData, setFormData] = useState({
    ...data,
    id: newRowId,
  })

  const [isLoading, setIsLoading] = useState(false)
  const [touched, setTouched] = useState(false)
  const [results, setResults] = useState([])
  const [controlValue, setControlValue] = useState('')

  useEffect(() => {
    setFormData({
      ...data,
      id: newRowId,
    })
  }, [data, newRowId])

  const onFieldChange = (_, { name, value }) => {
    setFormData(prevState => ({
      ...prevState,
      [name]: value,
    }))
    setTouched(true)
  }

  const onSearchTextChange = (e, { value }) => {
    setControlValue(value)
    setIsLoading(true)
    searchData(value)
  }

  const searchData = debounce((value) => {
    if (value.length > 0) {
      internalRequest({
        url: '/api/persons/search',
        method: 'get',
        queryParams: { wildcard: value },
        onSuccess: (resp) => {
          setResults(resp.map(r => ({
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
          })))
          setIsLoading(false)
        },
        onFail: () => {
          setIsLoading(false)
          setControlValue(value)
        },
      })
    } else {
      setIsLoading(false)
    }
  }, 250)

  const personSelectHandler = (e, { result }) => {
    setFormData(prevState => ({
      ...prevState,
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
    }))
    setTouched(true)
  }

  const saveHandler = () => {
    onSave(formData, newRowId)
  }

  const asOption = ([k, v]) => ({ value: k, text: localize(v) })

  const personMandatoryFields = config.mandatoryFields.Person
  const isMandatoryFieldEmpty =
    (personMandatoryFields.GivenName && !formData.givenName) ||
    (personMandatoryFields.Surname && !formData.surname) ||
    (personMandatoryFields.PersonalId && !formData.personalId) ||
    (personMandatoryFields.MiddleName && !formData.middleName) ||
    (personMandatoryFields.BirthDate && !formData.birthDate) ||
    (personMandatoryFields.Role && !formData.role) ||
    (personMandatoryFields.CountryId && !formData.countryId) ||
    (personMandatoryFields.PhoneNumber && !formData.phoneNumber) ||
    (personMandatoryFields.PhoneNumber1 && !formData.phoneNumber1) ||
    (personMandatoryFields.Address && !formData.address) ||
    (personMandatoryFields.Sex && !formData.sex)

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
                value={formData.role}
                name="role"
                required={personMandatoryFields.Role}
                onChange={onFieldChange}
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
                  onResultSelect={personSelectHandler}
                  onSearchChange={onSearchTextChange}
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
                value={formData.givenName}
                onChange={onFieldChange}
                disabled={disabled}
                readOnly={formData.personSelected}
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
                value={formData.surname}
                onChange={onFieldChange}
                disabled={disabled}
                readOnly={formData.personSelected}
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
                value={formData.personalId}
                onChange={onFieldChange}
                disabled={disabled || formData.personSelected}
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
                value={formData.middleName}
                onChange={onFieldChange}
                disabled={disabled || formData.personSelected}
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
                value={formData.birthDate}
                onChange={onFieldChange}
                disabled={disabled || formData.personSelected}
                localize={localize}
                required={personMandatoryFields.BirthDate}
              />
            </div>
            <div className="field" data-tooltip={localize('SexTooltip')} data-position="top left">
              <Form.Select
                name="sex"
                label={localize('Sex')}
                placeholder={localize('Sex')}
                value={formData.sex}
                onChange={onFieldChange}
                options={options.sex.map(asOption)}
                disabled={disabled || formData.personSelected}
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
                value={formData.countryId}
                name="countryId"
                key="countryId"
                required={personMandatoryFields.CountryId}
                search
                onChange={onFieldChange}
                disabled={disabled || formData.personSelected}
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
                value={formData.phoneNumber}
                onChange={onFieldChange}
                disabled={disabled || formData.personSelected}
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
                value={formData.phoneNumber1}
                onChange={onFieldChange}
                disabled={disabled || formData.personSelected}
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
                value={formData.address}
                onChange={onFieldChange}
                disabled={disabled || formData.personSelected}
                required={personMandatoryFields.Address}
                autoComplete="off"
              />
            </div>
          </Form.Group>

          <div>
            {isMandatoryFieldEmpty && <Message content={localize('FixErrorsBeforeSubmit')} error />}
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
                    onClick={saveHandler}
                    disabled={disabled || isMandatoryFieldEmpty || !touched}
                  />
                </div>
                <div data-tooltip={localize('ButtonCancel')} data-position="top center">
                  <Button icon="cancel" color="red" onClick={onCancel} disabled={disabled} />
                </div>
              </Button.Group>
            </div>
          </Form.Group>
        </Form>
      </Table.Cell>
    </Table.Row>
  )
}

PersonEdit.propTypes = {
  data: PropTypes.shape({
    id: PropTypes.number,
    givenName: PropTypes.string.isRequired,
    personalId: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    surname: PropTypes.string.isRequired,
    middleName: PropTypes.string,
    birthDate: PropTypes.string,
    sex: PropTypes.oneOfType([PropTypes.string, PropTypes.number]).isRequired,
    role: PropTypes.oneOfType([PropTypes.string, PropTypes.number]).isRequired,
    countryId: PropTypes.oneOfType([PropTypes.string, PropTypes.number]).isRequired,
    phoneNumber: PropTypes.oneOfType([PropTypes.string, PropTypes.number]).isRequired,
    phoneNumber1: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    address: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    personSelected: PropTypes.bool,
  }),
  newRowId: PropTypes.number,
  onSave: PropTypes.func.isRequired,
  onCancel: PropTypes.func.isRequired,
  localize: PropTypes.func.isRequired,
  locale: PropTypes.string,
  countries: PropTypes.arrayOf(PropTypes.shape({})),
  roles: PropTypes.arrayOf(PropTypes.shape({})),
  disabled: PropTypes.bool,
}

PersonEdit.defaultProps = {
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

export default PersonEdit
