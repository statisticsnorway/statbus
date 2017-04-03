import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Icon } from 'semantic-ui-react'

import statUnitTypes from 'helpers/statUnitTypes'
import getField from 'components/getField'
import { wrapper } from 'helpers/locale'
import { getModel } from 'helpers/modelProperties'
import fieldsRenderer from '../FieldsRenderer'
import styles from './styles.pcss'

const { shape, func, number } = React.PropTypes

class CreateStatUnitPage extends React.Component {

  static propTypes = {
    actions: shape({
      changeType: func.isRequired,
      submitStatUnit: func.isRequired,
    }).isRequired,
    type: number.isRequired,
    localize: func.isRequired,
    statUnitModel: shape().isRequired,
  }

  componentDidMount() {
    const { actions, type } = this.props
    actions.getModel(type)
  }

  componentWillReceiveProps(newProps) {
    const { actions, type } = this.props
    const { type: newType } = newProps
    if (newType !== type) {
      actions.getModel(newType)
    }
  }

  handleOnChange = (e, { name, value }) => {
    this.props.actions.editForm({ name, value })
  }

  handleSubmit = (e) => {
    e.preventDefault()
    const { type, statUnitModel, actions: { submitStatUnit } } = this.props
    const data = { ...getModel(statUnitModel.properties), type }
    submitStatUnit(data)
  }

  renderForm() {
    const { errors, statUnitModel, type, localize } = this.props

    const renderSubmitButton = () => (
      <Button
        content={localize('Submit')}
        key="create_stat_unit_submit_btn"
        type="submit"
        floated="right"
        primary
      />
    )

    const renderBackButton = () => (
      <Button
        as={Link} to="/statunits"
        content={localize('Back')}
        icon={<Icon size="large" name="chevron left" />}
        floated="left"
        size="small"
        color="grey"
        type="button"
        key="create_stat_unit_back_btn"
      />
    )

    const children = [
      fieldsRenderer(statUnitModel.properties, errors, this.handleOnChange, localize),
      <br key="create_stat_unit_br" />,
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
    const { actions: { changeType }, type, localize } = this.props

    const statUnitTypeOptions =
      [...statUnitTypes].map(([key, value]) => ({ value: key, text: localize(value) }))

    const handleTypeEdit = (e, { value }) => {
      if (type !== value) changeType(value)
    }

    return (
      <div className={styles.edit}>
        <Form.Select
          name="type"
          options={statUnitTypeOptions}
          value={type}
          onChange={handleTypeEdit}
        />
        <br />
        {this.renderForm()}
      </div>
    )
  }
}

export default wrapper(CreateStatUnitPage)
