import React from 'react'
import { Form, Message, Button, Icon, Segment, Header, Popup } from 'semantic-ui-react'
import { arrayOf, func, shape, string, bool } from 'prop-types'
import { equals } from 'ramda'

import config from 'helpers/config'
import { hasValue } from 'helpers/validation'
import { SelectField } from 'components/fields'

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

class AddressField extends React.Component {
  static propTypes = {
    name: string.isRequired,
    label: string.isRequired,
    value: shape(),
    errors: arrayOf(string),
    disabled: bool,
    onChange: func.isRequired,
    localize: func.isRequired,
    required: bool,
    popuplocalizedKey: string,
  }

  static defaultProps = {
    value: null,
    errors: [],
    disabled: false,
    required: false,
    popuplocalizedKey: undefined,
  }

  state = {
    value: ensureAddress(this.props.value),
    msgFailFetchAddress: undefined,
    editing: false,
    touched: false,
  }

  componentWillReceiveProps(nextProps) {
    if (!equals(this.state.value, nextProps.value)) {
      this.setState({ value: ensureAddress(nextProps.value) })
    }
  }

  handleEdit = (e, { name, value }) => {
    this.setState(s => ({ value: { ...s.value, [name]: value }, touched: true }))
  }

  startEditing = () => {
    this.setState({ editing: true })
  }

  doneEditing = (e) => {
    e.preventDefault()
    const { onChange, name } = this.props
    const { value } = this.state
    this.setState({ editing: false, touched: false }, () => {
      onChange({ target: { name, value } }, { ...this.props, value })
    })
  }

  cancelEditing = (e) => {
    e.preventDefault()
    const { onChange, name, value } = this.props
    this.setState({ editing: false }, () => {
      onChange({ target: { name, value } }, this.props)
    })
  }

  regionSelectedHandler = (_, { value: regionId }) => {
    this.setState(s => ({ value: { ...s.value, regionId }, touched: true }))
  }

  render() {
    const { localize, name, label: labelKey, errors: errorKeys, disabled, required } = this.props
    const { value, editing, msgFailFetchAddress, touched } = this.state
    const label = localize(labelKey)
    const latitudeIsBad = !validateLatitude(value.latitude)
    const longitudeIsBad = !validateLongitude(value.longitude)
    return (
      <Segment.Group as={Form.Field}>
        <label className={required ? 'is-required' : undefined} htmlFor={name}>
          {label}
        </label>
        <Segment.Group>
          <Segment>
            <SelectField
              name="regionId"
              label="Region"
              lookup={12}
              onChange={this.regionSelectedHandler}
              value={this.state.value.regionId}
              localize={localize}
              required={mandatoryField.GeographicalCodes}
              disabled={disabled || !editing}
            />
            <br />
            <Form.Group widths="equal">
              <Form.Input
                name="addressPart1"
                value={value.addressPart1 || ''}
                label={localize('AddressPart1')}
                placeholder={localize('AddressPart1')}
                onChange={this.handleEdit}
                required={mandatoryField.AddressPart1}
                disabled={disabled || !editing}
              />
              <Form.Input
                name="addressPart2"
                value={value.addressPart2 || ''}
                label={localize('AddressPart2')}
                placeholder={localize('AddressPart2')}
                onChange={this.handleEdit}
                required={mandatoryField.AddressPart2}
                disabled={disabled || !editing}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Input
                name="addressPart3"
                value={value.addressPart3 || ''}
                label={localize('AddressPart3')}
                placeholder={localize('AddressPart3')}
                onChange={this.handleEdit}
                required={mandatoryField.AddressPart3}
                disabled={disabled || !editing}
              />
            </Form.Group>
            <Header as="h5" content={localize('GpsCoordinates')} dividing />
            <Form.Group widths="equal">
              <Popup
                trigger={
                  <Form.Input
                    name="latitude"
                    type="text"
                    value={value.latitude || ''}
                    onChange={this.handleEdit}
                    label={localize('Latitude')}
                    placeholder={localize('Latitude')}
                    required={mandatoryField.latitude}
                    disabled={disabled || !editing}
                    maxLength={10}
                    min="-90"
                    max="90"
                  />
                }
                content={localize('BadLatitude')}
                open={
                  hasValue(value.latitude) &&
                  editing &&
                  (value.latitude.length === 10 || latitudeIsBad)
                }
              />
              <Popup
                trigger={
                  <Form.Input
                    name="longitude"
                    type="text"
                    value={value.longitude || ''}
                    onChange={this.handleEdit}
                    label={localize('Longitude')}
                    placeholder={localize('Longitude')}
                    required={mandatoryField.longitude}
                    disabled={disabled || !editing}
                    maxLength={11}
                    min="-180"
                    max="180"
                  />
                }
                content={localize('BadLongitude')}
                open={
                  hasValue(value.longitude) &&
                  editing &&
                  (value.longitude.length === 11 || longitudeIsBad)
                }
              />
            </Form.Group>
          </Segment>
          <Segment clearing>
            {editing ? (
              <Button.Group floated="right">
                <div data-tooltip={localize('ButtonSave')} data-position="top center">
                  <Button
                    type="button"
                    icon={<Icon name="check" />}
                    onClick={this.doneEditing}
                    color="green"
                    size="small"
                    disabled={
                      disabled ||
                      !value.regionId ||
                      (value.latitude && latitudeIsBad) ||
                      (value.longitude && longitudeIsBad) ||
                      !touched
                    }
                  />
                </div>
                <div data-tooltip={localize('ButtonCancel')} data-position="top center">
                  <Button
                    type="button"
                    icon={<Icon name="cancel" />}
                    onClick={this.cancelEditing}
                    color="red"
                    size="small"
                    disabled={disabled}
                  />
                </div>
              </Button.Group>
            ) : (
              <Button.Group floated="right">
                <div data-tooltip={localize('EditButton')} data-position="top center">
                  <Button
                    type="button"
                    icon={<Icon name="edit" />}
                    onClick={this.startEditing}
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
        {hasValue(errorKeys) && <Message title={label} list={errorKeys.map(localize)} error />}
      </Segment.Group>
    )
  }
}

export default AddressField
