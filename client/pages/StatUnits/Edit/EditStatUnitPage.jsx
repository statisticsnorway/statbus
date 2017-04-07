import React from 'react'
import { Link } from 'react-router'
import {
  Button,
  Icon,
  Modal,
  Radio,
  TextArea,
  Grid,
  Form,
} from 'semantic-ui-react'
import R from 'ramda'

import { getModel } from 'helpers/modelProperties'
import { wrapper } from 'helpers/locale'
import fieldsRenderer from '../FieldsRenderer'
import styles from './styles.pcss'

const { string, shape, func } = React.PropTypes
class EditStatUnitPage extends React.Component {

  static propTypes = {
    id: string.isRequired,
    type: string.isRequired,
    actions: shape({ fetchStatUnit: func }).isRequired,
    localize: func.isRequired,
    statUnit: shape().isRequired,
  }

  state = {
    open: false,
    reason: '1',
    comment: '',
  }

  componentDidMount() {
    const { actions: {
        fetchStatUnit,
      }, id, type } = this.props
    fetchStatUnit(type, id)
  }

  shouldComponentUpdate(nextProps, nextState) {
    return this.props.localize.lang !== nextProps.localize.lang
      || !R.equals(this.props, nextProps)
      || !R.equals(this.state, nextState)
  }

  onChangeComment = (e, { value }) => this.setState({ comment: value })

  handleOnChange = (e, { name, value }) => {
    this
      .props
      .actions
      .editForm({ name, value })
  }

  handleSubmit = () => {
    const { type, id, statUnit, actions: {
        submitStatUnit,
      } } = this.props
    const reason = this.state.reason
    const comment = this.state.comment
    this.setState({ comment: '', reason: '1' })
    const data = {
      ...getModel(statUnit),
      regId: id,
      changeReason: reason,
      editComment: comment,
    }
    submitStatUnit(type, data)
  }

  showModal = (e) => {
    e.preventDefault()
    this.setState({ open: true })
  }

  closeModal = () => this.setState({ open: false })

  toggleReason = (e, { value }) => this.setState({ reason: value })

  renderForm() {
    const { errors, statUnit, type, localize } = this.props

    const renderBackButton = () => (
      <Button
        as={Link}
        to="/statunits"
        content={localize('Back')}
        icon={<Icon size="large" name="chevron left" />}
        floated="left"
        size="small"
        color="grey"
        type="button"
        key="edit_stat_unit_back_btn"
      />
    )

    const renderSubmitButton = () => (<Button
      key="edit_stat_unit_submit_btn"
      content={localize('Submit')}
      floated="right"
      type="submit"
      primary
    />)

    const editors = fieldsRenderer(statUnit.properties, errors, this.handleOnChange, localize)

    const children = [
      ...editors,
      <br key="edit_stat_unit_br" />,
      renderBackButton(),
      renderSubmitButton(),
    ]

    return (
      <Form
        className={styles.form}
        onSubmit={this.showModal}
      >{children}</Form>
    )
  }

  render() {
    const { localize } = this.props
    return (
      <div className={styles.edit}>
        {this.renderForm()}
        <Modal open={this.state.open}>
          <Modal.Header>
            {this.state.reason === '1' ? localize('CommentIsMandatory') : localize('CommentIsNotMandatory')
            }</Modal.Header>
          <Modal.Content>
            <Grid>
              <Grid.Row>
                <Grid.Column width="3">
                  <Radio
                    label={localize('Editing')}
                    name="radioGroup"
                    value="1"
                    checked={this.state.reason === '1'}
                    onChange={this.toggleReason}
                  />
                  <Radio
                    label={localize('Correcting')}
                    name="radioGroup"
                    value="2"
                    checked={this.state.reason === '2'}
                    onChange={this.toggleReason}
                  />
                  <br key="modal_reason_radio_br" />
                  <Icon name={this.state.reason === '1' ? 'edit' : 'write'} size="massive" />
                </Grid.Column>
                <Grid.Column width="13">
                  <Form>
                    <TextArea
                      rows="8"
                      value={this.state.comment}
                      onChange={this.onChangeComment}
                    />
                  </Form>
                </Grid.Column>
              </Grid.Row>
            </Grid>
          </Modal.Content>
          <Modal.Actions>
            <Button.Group>
              <Button negative onClick={this.closeModal}>{localize('ButtonCancel')}</Button>
              <Button
                positive
                onClick={this.handleSubmit}
                disabled={this.state.reason === '1' && this.state.comment === ''}
              >{localize('Submit')}
              </Button>
            </Button.Group>
          </Modal.Actions>
        </Modal>
      </div>
    )
  }
}

export default wrapper(EditStatUnitPage)
