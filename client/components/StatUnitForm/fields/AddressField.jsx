import React from 'react'
import { Form, Message, Button, Icon, Segment } from 'semantic-ui-react'
import { arrayOf, func, shape, string } from 'prop-types'

import RegionField from './RegionField'

const defaultAddressState = {
  id: 0,
  addressPart1: '',
  addressPart2: '',
  addressPart3: '',
  region: { code: '', name: '' },
  gpsCoordinates: '',
}

class AddressField extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    onChange: func.isRequired,
    name: string.isRequired,
    errors: arrayOf(string),
    value: shape(),
  }

  static defaultProps = {
    value: null,
    errors: [],
  }

  state = {
    value: this.props.value || defaultAddressState,
    msgFailFetchAddress: undefined,
    editing: false,
  }

  handleEdit = (e, { name, value }) => {
    this.setState(s => ({ value: { ...s.value, [name]: value } }))
  }

  startEditing = () => {
    this.setState({ editing: true })
  }

  doneEditing = (e) => {
    e.preventDefault()
    const { onChange, name: fieldName } = this.props
    onChange({ name: fieldName, value: this.state.value })
    this.setState({ editing: false })
  }

  cancelEditing = (e) => {
    e.preventDefault()
    const { onChange, name: fieldName, value } = this.props
    onChange({ name: fieldName, value })
    this.setState({ editing: false })
  }

  regionSelectedHandler = (region) => {
    this.setState(s => ({ value: { ...s.value, region } }))
  }

  render() {
    const { localize, name, errors } = this.props
    const { value, editing, msgFailFetchAddress } = this.state
    const attrs = editing ? { required: true } : { disabled: true }
    const label = localize(name)
    return (
      <Segment.Group as={Form.Field}>
        <Segment>{label}</Segment>
        <Segment.Group>
          <Segment>
            <RegionField
              localize={localize}
              onRegionSelected={this.regionSelectedHandler}
              name="regionSelector"
              editing={this.state.editing}
              data={this.state.value.region}
            />
            <Form.Group widths="equal">
              <Form.Input
                name="addressPart1"
                value={value.addressPart1}
                label={`${localize('AddressPart')} 1`}
                placeholder={`${localize('AddressPart')} 1`}
                onChange={this.handleEdit}
                {...attrs}
              />
              <Form.Input
                name="addressPart2"
                value={value.addressPart2}
                label={`${localize('AddressPart')} 2`}
                placeholder={`${localize('AddressPart')} 2`}
                onChange={this.handleEdit}
                {...attrs}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Input
                name="addressPart3"
                value={value.addressPart3}
                label={`${localize('AddressPart')} 3`}
                placeholder={`${localize('AddressPart')} 3`}
                onChange={this.handleEdit}
                {...attrs}
              />
              <Form.Input
                name="gpsCoordinates"
                value={value.gpsCoordinates}
                onChange={this.handleEdit}
                label={localize('GpsCoordinates')}
                placeholder={localize('GpsCoordinates')}
                disabled={!editing}
              />
            </Form.Group>
            <Form.Input
              control={Message}
              name="regionCode"
              label={localize('RegionCode')}
              info
              size="mini"
              header={this.state.value.region.code || localize('RegionCode')}
              disabled={!editing}
            />
          </Segment>
          <Segment clearing>
            {editing ?
              <Button.Group floated="right">
                <Button
                  type="button"
                  icon={<Icon name="check" />}
                  onClick={this.doneEditing}
                  color="green"
                  size="small"
                  disabled={!this.state.value.region.code ||
                    !(value.addressPart1 && value.addressPart2 && value.addressPart3)}
                />
                <Button
                  type="button"
                  icon={<Icon name="cancel" />}
                  onClick={this.cancelEditing}
                  color="red"
                  size="small"
                />
              </Button.Group> :
              <Button.Group floated="right">
                <Button
                  type="button"
                  icon={<Icon name="edit" />}
                  onClick={this.startEditing}
                  color="blue"
                  size="small"
                />
              </Button.Group>}
          </Segment>
        </Segment.Group>
        {msgFailFetchAddress && <Message error content={msgFailFetchAddress} />}
        {errors.length !== 0 && <Message error title={label} list={errors.map(localize)} />}
      </Segment.Group>
    )
  }
}

export default AddressField
