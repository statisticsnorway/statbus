import React from 'react'
import { Form, Message, Button, Icon, Segment } from 'semantic-ui-react'
import { arrayOf, func, shape, string, bool } from 'prop-types'
import { equals } from 'ramda'

import { hasValue } from 'helpers/validation'
import SelectField from '../fields/SelectField'

const defaultAddressState = {
  id: 0,
  addressPart1: '',
  addressPart2: '',
  addressPart3: '',
  regionId: undefined,
  gpsCoordinates: '',
}

const ensureAddress = value => value || defaultAddressState

class AddressField extends React.Component {
  static propTypes = {
    name: string.isRequired,
    label: string.isRequired,
    value: shape(),
    errors: arrayOf(string),
    disabled: bool,
    setFieldValue: func.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    value: null,
    errors: [],
    disabled: false,
  }

  state = {
    value: ensureAddress(this.props.value),
    msgFailFetchAddress: undefined,
    editing: false,
  }

  componentWillReceiveProps(nextProps) {
    if (!equals(this.state.value, nextProps.value)) {
      this.setState({ value: ensureAddress(nextProps.value) })
    }
  }

  handleEdit = (e, { name, value }) => {
    this.setState(s => ({ value: { ...s.value, [name]: value } }))
  }

  startEditing = () => {
    this.setState({ editing: true })
  }

  doneEditing = (e) => {
    e.preventDefault()
    const { setFieldValue, name } = this.props
    this.setState({ editing: false }, () => {
      setFieldValue(name, this.state.value)
    })
  }

  cancelEditing = (e) => {
    e.preventDefault()
    const { setFieldValue, name, value } = this.props
    this.setState({ editing: false }, () => {
      setFieldValue(name, value)
    })
  }

  regionSelectedHandler = (e, value) => {
    this.setState(s => ({ value: { ...s.value, regionId: value } }))
  }

  render() {
    const { localize, name, label: labelKey, errors: errorKeys, disabled } = this.props
    const { value, editing, msgFailFetchAddress } = this.state
    const attrs = editing ? { required: true } : { disabled: true }
    if (editing && disabled) attrs.disabled = true
    const label = localize(labelKey)
    return (
      <Segment.Group as={Form.Field}>
        <label htmlFor={name}>{label}</label>
        <Segment.Group>
          <Segment>
            <SelectField
              name="regionId"
              label="Region"
              lookup={11}
              setFieldValue={this.regionSelectedHandler}
              value={this.state.value.regionId}
              localize={localize}
              touched={false}
              required
              disabled={disabled || !editing}
            />
            <Form.Group widths="equal">
              <Form.Input
                name="addressPart1"
                value={value.addressPart1 || ''}
                label={`${localize('AddressPart')} 1`}
                placeholder={`${localize('AddressPart')} 1`}
                onChange={this.handleEdit}
                {...attrs}
              />
              <Form.Input
                name="addressPart2"
                value={value.addressPart2 || ''}
                label={`${localize('AddressPart')} 2`}
                placeholder={`${localize('AddressPart')} 2`}
                onChange={this.handleEdit}
                {...attrs}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Input
                name="addressPart3"
                value={value.addressPart3 || ''}
                label={`${localize('AddressPart')} 3`}
                placeholder={`${localize('AddressPart')} 3`}
                onChange={this.handleEdit}
                {...attrs}
              />
              <Form.Input
                name="gpsCoordinates"
                value={value.gpsCoordinates || ''}
                onChange={this.handleEdit}
                label={localize('GpsCoordinates')}
                placeholder={localize('GpsCoordinates')}
                disabled={disabled || !editing}
              />
            </Form.Group>
          </Segment>
          <Segment clearing>
            {editing ? (
              <Button.Group floated="right">
                <Button
                  type="button"
                  icon={<Icon name="check" />}
                  onClick={this.doneEditing}
                  color="green"
                  size="small"
                  disabled={
                    disabled ||
                    !this.state.value.regionId ||
                    !(value.addressPart1 && value.addressPart2 && value.addressPart3)
                  }
                />
                <Button
                  type="button"
                  icon={<Icon name="cancel" />}
                  onClick={this.cancelEditing}
                  color="red"
                  size="small"
                  disabled={disabled}
                />
              </Button.Group>
            ) : (
              <Button.Group floated="right">
                <Button
                  type="button"
                  icon={<Icon name="edit" />}
                  onClick={this.startEditing}
                  color="blue"
                  size="small"
                  disabled={disabled}
                />
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
