import React from 'react'
import { Link } from 'react-router'
import { Button, Icon, Form } from 'semantic-ui-react'
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
    actions: shape({
      fetchStatUnit: func,
    }).isRequired,
    localize: func.isRequired,
    statUnit: shape().isRequired,
  }

  componentDidMount() {
    const { actions: { fetchStatUnit }, id, type } = this.props
    fetchStatUnit(type, id)
  }

  shouldComponentUpdate(nextProps, nextState) {
    return this.props.localize.lang !== nextProps.localize.lang
      || !R.equals(this.props, nextProps)
      || !R.equals(this.state, nextState)
  }

  handleOnChange = (e, { name, value }) => {
    this.props.actions.editForm({ name, value })
  }

  handleSubmit = (e) => {
    e.preventDefault()
    const { type, id, statUnit, actions: { submitStatUnit } } = this.props
    const data = { ...getModel(statUnit), regId: id }
    submitStatUnit(type, data)
  }

  renderForm() {
    const { errors, statUnit, type, localize } = this.props

    const renderBackButton = () => (
      <Button
        as={Link} to="/statunits"
        content={localize('Back')}
        icon={<Icon size="large" name="chevron left" />}
        floated="left"
        size="small"
        color="grey"
        type="button"
        key="edit_stat_unit_back_btn"
      />
    )

    const renderSubmitButton = () => (
      <Button
        key="edit_stat_unit_submit_btn"
        content={localize('Submit')}
        floated="right"
        type="submit"
        primary
      />
    )

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
        onSubmit={this.handleSubmit}
      >{children}</Form>
    )
  }

  render() {
    return (
      <div className={styles.edit}>
        {this.renderForm()}
      </div>
    )
  }
}

export default wrapper(EditStatUnitPage)
