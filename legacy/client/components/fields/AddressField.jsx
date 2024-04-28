import React, { useState, useEffect } from 'react'
import { Form, Message, Button, Icon, Segment, Header, Popup } from 'semantic-ui-react'
import { arrayOf, func, shape, string, bool } from 'prop-types'
import { equals } from 'ramda'

import config from '/helpers/config'
import { hasValue } from '/helpers/validation'
import { SelectField } from '/components/fields'

const defaultAddressState = {
  id: 0,
  addressPart1: '',
  addressPart2: '',
  addressPart3: '',
  regionId: undefined,
  latitude: 0,
  longitude: 0,
}

const ensureAddress = value => value || defaultAddressState
const mandatoryField = config.mandatoryFields.Addresses
const regLatitude = /^-?(\+|-)?(?:90(?:(?:\.0{1,6})?)|(?:[0-9]|[1-8][0-9])(?:(?:\.[0-9]{1,6})?))$/
const regLongitude = /^(\+|-)?(?:180(?:(?:\.0{1,6})?)|(?:[0-9]|[1-9][0-9]|1[0-7][0-9])(?:(?:\.[0-9]{1,6})?))$/
const validateLatitude = latitude => latitude === null || regLatitude.exec(latitude)
const validateLongitude = longitude => longitude === null || regLongitude.exec(longitude)

export function AddressField({
  name,
  label,
  value,
  errors,
  disabled,
  onChange,
  localize,
  required,
  locale,
  popuplocalizedKey,
}) {
  const [addressValue, setAddressValue] = useState(ensureAddress(value))
  const [msgFailFetchAddress, setMsgFailFetchAddress] = useState(undefined)
  const [editing, setEditing] = useState(false)
  const [touched, setTouched] = useState(false)

  useEffect(() => {
    if (!equals(addressValue, value)) {
      setAddressValue(ensureAddress(value))
    }
  }, [value])

  const handleEdit = (e, { name, value }) => {
    setAddressValue(prevState => ({ ...prevState, [name]: value }))
    setTouched(true)
  }

  const startEditing = () => {
    setEditing(true)
  }

  const doneEditing = (e) => {
    e.preventDefault()
    const { name } = props
    onChange({ target: { name, value: addressValue } }, { ...props, value: addressValue })
    setEditing(false)
    setTouched(false)
  }

  const cancelEditing = (e) => {
    e.preventDefault()
    setAddressValue(ensureAddress(value))
    setEditing(false)
  }

  const regionSelectedHandler = (_, { value: regionId }) => {
    setAddressValue(prevState => ({ ...prevState, regionId }))
    setTouched(true)
  }

  const latitudeIsBad = !validateLatitude(addressValue.latitude)
  const longitudeIsBad = !validateLongitude(addressValue.longitude)
  const isShowFieldsRequired = editing || required
  const isMandatoryFieldEmpty =
    isShowFieldsRequired &&
    ((mandatoryField.GeographicalCodes && !addressValue.regionId) ||
      (mandatoryField.AddressPart1 && !addressValue.addressPart1) ||
      (mandatoryField.AddressPart2 && !addressValue.addressPart2) ||
      (mandatoryField.AddressPart3 && !addressValue.addressPart3) ||
      (mandatoryField.Latitude && !addressValue.latitude) ||
      (mandatoryField.Longitude && !addressValue.longitude))

  return (
    <Segment.Group as={Form.Field}>
      <label className={required ? 'is-required' : undefined} htmlFor={name}>
        {label}
      </label>
      <Segment.Group>
        <Segment>
          <div data-tooltip={localize('RegionIdTooltip')} data-position="top left">
            <SelectField
              name="regionId"
              label="Region"
              lookup={12}
              locale={locale}
              onChange={regionSelectedHandler}
              value={addressValue.regionId}
              localize={localize}
              required={isShowFieldsRequired && mandatoryField.GeographicalCodes}
              disabled={disabled || !editing}
            />
          </div>

          <br />
          <Form.Group widths="equal">
            <div
              className="field"
              data-tooltip={localize('AddressPart1Tooltip')}
              data-position="top left"
            >
              <Form.Input
                name="addressPart1"
                value={addressValue.addressPart1 || ''}
                label={localize('AddressPart1')}
                placeholder={localize('AddressPart1')}
                onChange={handleEdit}
                required={isShowFieldsRequired && mandatoryField.AddressPart1}
                disabled={disabled || !editing}
                autoComplete="off"
              />
            </div>
            <div
              className="field"
              data-tooltip={localize('AddressPart2Tooltip')}
              data-position="top left"
            >
              <Form.Input
                name="addressPart2"
                value={addressValue.addressPart2 || ''}
                label={localize('AddressPart2')}
                placeholder={localize('AddressPart2')}
                onChange={handleEdit}
                required={isShowFieldsRequired && mandatoryField.AddressPart2}
                disabled={disabled || !editing}
                autoComplete="off"
              />
            </div>
          </Form.Group>
          <Form.Group widths="equal">
            <div
              className="field"
              data-tooltip={localize('AddressPart3Tooltip')}
              data-position="top left"
            >
              <Form.Input
                name="addressPart3"
                value={addressValue.addressPart3 || ''}
                label={localize('AddressPart3')}
                placeholder={localize('AddressPart3')}
                onChange={handleEdit}
                required={isShowFieldsRequired && mandatoryField.AddressPart3}
                disabled={disabled || !editing}
                autoComplete="off"
              />
            </div>
          </Form.Group>
          <Header
            as="h5"
            content={localize('GpsCoordinates')}
            style={{ opacity: `${editing ? 1 : 0.25}` }}
            dividing
          />
          <Form.Group widths="equal">
            <div
              className="field"
              data-tooltip={localize('LatitudeTooltip')}
              data-position="top left"
            >
              <Popup
                trigger={
                  <Form.Input
                    name="latitude"
                    type="text"
                    value={addressValue.latitude || ''}
                    onChange={handleEdit}
                    label={localize('Latitude')}
                    placeholder={localize('Latitude')}
                    required={isShowFieldsRequired && mandatoryField.Latitude}
                    disabled={disabled || !editing}
                    maxLength={10}
                    min="-90"
                    max="90"
                    autoComplete="off"
                  />
                }
                content={localize('BadLatitude')}
                open={
                  hasValue(addressValue.latitude) &&
                  editing &&
                  (addressValue.latitude.length === 10 || latitudeIsBad)
                }
              />
            </div>
            <div
              className="field"
              data-tooltip={localize('LongitudeTooltip')}
              data-position="top left"
            >
              <Popup
                trigger={
                  <Form.Input
                    name="longitude"
                    type="text"
                    value={addressValue.longitude || ''}
                    onChange={handleEdit}
                    label={localize('Longitude')}
                    placeholder={localize('Longitude')}
                    required={isShowFieldsRequired && mandatoryField.Longitude}
                    disabled={disabled || !editing}
                    maxLength={11}
                    min="-180"
                    max="180"
                    autoComplete="off"
                  />
                }
                content={localize('BadLongitude')}
                open={
                  hasValue(addressValue.longitude) &&
                  editing &&
                  (addressValue.longitude.length === 11 || longitudeIsBad)
                }
              />
            </div>
          </Form.Group>
        </Segment>
        <Segment clearing>
          {editing ? (
            <div>
              {(isMandatoryFieldEmpty ||
                (!!addressValue.latitude && latitudeIsBad) ||
                (!!addressValue.longitude && longitudeIsBad)) && (
                <Message content={localize('FixErrorsBeforeSubmit')} error />
              )}
              <Button.Group floated="right">
                <div data-tooltip={localize('ButtonSave')} data-position="top center">
                  <Button
                    type="button"
                    icon={<Icon name="check" />}
                    onClick={doneEditing}
                    color="green"
                    size="small"
                    disabled={
                      disabled ||
                      isMandatoryFieldEmpty ||
                      (addressValue.latitude && latitudeIsBad) ||
                      (addressValue.longitude && longitudeIsBad) ||
                      !touched
                    }
                  />
                </div>
                <div data-tooltip={localize('ButtonCancel')} data-position="top center">
                  <Button
                    type="button"
                    icon={<Icon name="cancel" />}
                    onClick={cancelEditing}
                    color="red"
                    size="small"
                    disabled={disabled}
                  />
                </div>
              </Button.Group>
            </div>
          ) : (
            <Button.Group floated="right">
              <div data-tooltip={localize('EditButton')} data-position="top center">
                <Button
                  type="button"
                  icon={<Icon name="edit" />}
                  onClick={startEditing}
                  color="blue"
                  size="small"
                  disabled={disabled}
                />
              </div>
            </Button.Group>
          )}
        </Segment>
      </Segment.Group>
      {msgFailFetchAddress && <Message content={msgFailFetchAddress} error />}
      {hasValue(errors) && <Message title={label} list={errors.map(localize)} error />}
    </Segment.Group>
  )
}

AddressField.propTypes = {
  name: string.isRequired,
  label: string.isRequired,
  value: shape(),
  errors: arrayOf(string),
  disabled: bool,
  onChange: func.isRequired,
  localize: func.isRequired,
  required: bool,
  locale: string.isRequired,
  popuplocalizedKey: string,
}

AddressField.defaultProps = {
  value: null,
  errors: [],
  disabled: false,
  required: false,
  popuplocalizedKey: undefined,
}
