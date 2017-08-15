import React from 'react'
import { Button, Icon, Modal, Checkbox, TextArea, Grid } from 'semantic-ui-react'
import { shape, func, string } from 'prop-types'

import { stripNullableFields } from 'helpers/schema'
import ConnectedForm from './ConnectedForm'
import styles from './styles.pcss'

// TODO: should be configurable
const stripStatUnitFields = stripNullableFields([
  'enterpriseUnitRegId',
  'enterpriseGroupRegId',
  'foreignParticipationCountryId',
  'legalUnitId',
  'entGroupId',
])

export default class EditStatUnitPage extends React.Component {

  static propTypes = {
    regId: string.isRequired,
    type: string.isRequired,
    actions: shape({
      fetchStatUnit: func.isRequired,
      submitStatUnit: func.isRequired,
    }).isRequired,
    localize: func.isRequired,
  }

  state = {
    open: false,
    reason: '1',
    comment: '',
    statUnitToSubmit: undefined,
  }

  componentDidMount() {
    this.props.actions.fetchStatUnit(this.props.type, this.props.regId)
  }

  handleSubmit = () => {
    const { type, regId, actions: { submitStatUnit } } = this.props
    const processedStatUnit = stripStatUnitFields(this.state.statUnitToSubmit)
    const data = {
      ...processedStatUnit,
      regId,
      changeReason: this.state.reason,
      editComment: this.state.comment,
    }
    submitStatUnit(type, data)
  }

  handleChangeComment = (_, { value }) => { this.setState({ comment: value }) }

  showModal = (statUnit) => { this.setState({ open: true, statUnitToSubmit: statUnit }) }

  closeModal = () => { this.setState({ open: false, statUnitToSubmit: undefined }) }

  handleReasonToggle = (_, { value }) => { this.setState({ reason: value }) }

  renderModal() {
    const { localize } = this.props
    const { comment, reason } = this.state
    const headerKey = reason === '1' ? 'CommentIsMandatory' : 'CommentIsNotMandatory'
    return (
      <Modal open={this.state.open}>
        <Modal.Header content={localize(headerKey)} />
        <Modal.Content>
          <Grid>
            <Grid.Row>
              <Grid.Column width="3">
                <Checkbox
                  name="radioGroup"
                  value="1"
                  checked={reason === '1'}
                  onChange={this.handleReasonToggle}
                  label={localize('Editing')}
                  radio
                />
                <Checkbox
                  name="radioGroup"
                  value="2"
                  checked={reason === '2'}
                  onChange={this.handleReasonToggle}
                  label={localize('Correcting')}
                  radio
                />
                <br key="modal_reason_radio_br" />
                <Icon name={reason === '1' ? 'edit' : 'write'} size="massive" />
              </Grid.Column>
              <Grid.Column width="13" className="ui form">
                <TextArea
                  value={comment}
                  onChange={this.handleChangeComment}
                  rows={8}
                />
              </Grid.Column>
            </Grid.Row>
          </Grid>
        </Modal.Content>
        <Modal.Actions>
          <Button.Group>
            <Button
              onClick={this.closeModal}
              content={localize('ButtonCancel')}
              negative
            />
            <Button
              onClick={this.handleSubmit}
              disabled={reason === '1' && comment === ''}
              content={localize('Submit')}
              positive
            />
          </Button.Group>
        </Modal.Actions>
      </Modal>
    )
  }

  render() {
    return (
      <div className={styles.root}>
        <ConnectedForm onSubmit={this.showModal} />
        {this.renderModal()}
      </div>
    )
  }
}
